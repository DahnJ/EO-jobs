{-# LANGUAGE ScopedTypeVariables #-}

-- | Cheap, no-LLM HTTP sweeps over the DB: link-rot (dead website/careers URLs)
-- and redirect detection (a site that now lands on a different company's domain
-- is likely acquired or rebranded). One green thread per URL: ~600 blocking
-- calls is what GHC's lightweight threads are for.
module EoJobs.Net
  ( regDomain
  , checkLinks
  , checkRedirects
  ) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (SomeAsyncException, SomeException (..), fromException, throwIO, try)
import Data.List (nub, sortOn)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Typeable (typeOf)
import EoJobs.Company
import EoJobs.Db
import EoJobs.StringRules (isBlank, utf16Order)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (Method, hUserAgent, methodGet, methodHead, statusCode)
import Network.URI (parseURI, uriAuthority, uriRegName)

data Reply = Reply {replyStatus :: Int, finalUrl :: Text}

-- | One request with redirects followed; throws on network errors, not on 4xx/5xx.
sendOnce :: Manager -> Int -> Method -> Text -> IO Reply
sendOnce manager timeoutSeconds verb url = do
  initial <- parseRequest (T.unpack url)
  let request =
        initial
          { method = verb
          , requestHeaders = [(hUserAgent, "Mozilla/5.0 (compatible; EO-jobs-linkcheck/1.0)")]
          , responseTimeout = responseTimeoutMicro (timeoutSeconds * 1000000)
          }
  withResponseHistory request manager $ \history ->
    pure
      Reply
        { replyStatus = statusCode (responseStatus (hrFinalResponse history))
        , finalUrl = T.pack (show (getUri (hrFinalRequest history)))
        }

-- | Run an action, turning synchronous exceptions into 'Left'; cancellation
-- (async exceptions) still propagates.
trySync :: IO a -> IO (Either SomeException a)
trySync action =
  try action >>= \case
    Left e | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
    other -> pure other

exceptionLabel :: SomeException -> Text
exceptionLabel e = case fromException e of
  Just (HttpExceptionRequest _ content) -> T.pack (takeWhile (/= ' ') (show content))
  Just (InvalidUrlException _ _) -> "InvalidUrlException"
  Nothing -> case e of SomeException inner -> T.pack (show (typeOf inner))

-- | @(alive, detail)@ for a URL: HEAD, falling back to GET when HEAD is refused
-- or fails. 403 and 416 mean "exists but blocks bots", so they count as alive.
alive :: Manager -> Int -> Text -> IO (Bool, Text)
alive manager timeoutSeconds url
  | not ("http" `T.isPrefixOf` url) = pure (False, "no-url")
  | otherwise = do
      firstTry <- trySync $ do
        headReply <- send methodHead
        if replyStatus headReply `elem` [403, 405, 416, 501]
          then judge . replyStatus <$> send methodGet
          else pure (judge (replyStatus headReply))
      case firstTry of
        Right verdict -> pure verdict
        Left _ -> either (\e -> (False, exceptionLabel e)) (judge . replyStatus) <$> trySync (send methodGet)
  where
    send verb = sendOnce manager timeoutSeconds verb url
    judge s = (s < 400 || s `elem` [403, 416], T.pack (show s))

-- | Naive registrable domain: the last 2 host labels (last 3 under common
-- two-part TLDs such as @co.uk@), without @www.@; "" when there is no host.
regDomain :: Text -> Text
regDomain url
  | length parts >= 3, secondLast `elem` ["co", "com", "org", "gov", "ac", "net"], lastLabel `elem` ["uk", "au", "nz", "za", "in", "br", "jp", "kr"] =
      T.intercalate "." (lastN 3)
  | length parts >= 2 = T.intercalate "." (lastN 2)
  | otherwise = host
  where
    withScheme = if "http" `T.isPrefixOf` url then url else "https://" <> url
    rawHost = maybe "" (T.pack . uriRegName) (parseURI (T.unpack withScheme) >>= uriAuthority)
    host = let lowered = T.toLower rawHost in fromMaybe lowered (T.stripPrefix "www." lowered)
    -- like Java's String.split, trailing empty labels are dropped
    parts = reverse (dropWhile T.null (reverse (T.splitOn "." host)))
    lastN n = drop (length parts - n) parts
    (secondLast, lastLabel) = case reverse parts of
      l : s : _ -> (s, l)
      _ -> ("", "")

-- | Final post-redirect URL of a site, or "" when unreachable.
finalOf :: Manager -> Int -> Text -> IO Text
finalOf manager timeoutSeconds url = do
  firstTry <- trySync $ do
    headReply <- send methodHead
    if isBlank (finalUrl headReply) then finalUrl <$> send methodGet else pure (finalUrl headReply)
  case firstTry of
    Right final -> pure final
    Left _ -> either (const "") finalUrl <$> trySync (send methodGet)
  where
    send verb = sendOnce manager timeoutSeconds verb url

padRight :: Int -> Text -> Text
padRight width t = t <> T.replicate (width - length (utf16Order t)) " "

-- | Link-rot sweep over website and careers URLs; report in @/tmp/linkrot.txt@.
checkLinks :: Bool -> Int -> IO ()
checkLinks listedOnly timeoutSeconds = do
  manager <- newTlsManager
  companies <- loadAll
  let targets =
        [ (slug, kind, url)
        | (slug, c) <- companies
        , not listedOnly || c.listed
        , (kind, url) <- ("website", c.website) : [("careers", u) | u <- c.careersUrls]
        ]
  results <- mapConcurrently (\(slug, kind, url) -> (slug, kind, url,) <$> alive manager timeoutSeconds url) targets
  let bad =
        sortOn (\(slug, kind, _, _) -> (utf16Order slug, utf16Order kind))
          [(slug, kind, url, detail) | (slug, kind, url, (ok, detail)) <- results, not ok]
  writeUtf8 "/tmp/linkrot.txt" $
    T.intercalate "\n" [slug <> "\t" <> kind <> "\t" <> detail <> "\t" <> url | (slug, kind, url, detail) <- bad] <> "\n"
  TIO.putStrLn
    ( "checked " <> showT (length targets) <> " urls across "
        <> showT (length (nub [slug | (slug, _, _) <- targets]))
        <> " companies; " <> showT (length bad) <> " dead/unreachable"
    )
  TIO.putStrLn "full report: /tmp/linkrot.txt"
  mapM_
    (\(slug, kind, url, detail) -> TIO.putStrLn ("  " <> padRight 30 slug <> " " <> padRight 8 kind <> " " <> padRight 14 detail <> " " <> url))
    (take 40 bad)

-- | Find listed sites that now redirect to a different domain; report in
-- @/tmp/redirects.txt@.
checkRedirects :: Int -> IO ()
checkRedirects timeoutSeconds = do
  manager <- newTlsManager
  companies <- loadAll
  let listedSites = [(slug, c.name, c.website) | (slug, c) <- companies, c.listed]
  finals <- mapConcurrently (\(_, _, web) -> finalOf manager timeoutSeconds web) listedSites
  let moved =
        sortOn (\(s, n, a, b) -> map utf16Order [s, n, a, b])
          [ (slug, name', from, to)
          | ((slug, name', web), final) <- zip listedSites finals
          , let from = regDomain web
          , let to = regDomain final
          , not (T.null from) && not (T.null to) && from /= to
          ]
  writeUtf8 "/tmp/redirects.txt" $
    T.intercalate "\n" [s <> "\t" <> n <> "\t" <> a <> " -> " <> b | (s, n, a, b) <- moved] <> "\n"
  TIO.putStrLn
    ( "checked " <> showT (length listedSites) <> " listed websites; "
        <> showT (length moved) <> " redirect to a DIFFERENT domain:\n"
    )
  mapM_ (\(_, n, a, b) -> TIO.putStrLn ("  " <> padRight 28 n <> " " <> a <> "  ->  " <> b)) moved

showT :: Show a => a -> Text
showT = T.pack . show
