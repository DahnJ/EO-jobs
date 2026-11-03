{-# LANGUAGE RecordWildCards #-}

-- | Apply verified inbox records (@companies/_inbox/*.json@) into the DB. Each
-- per-field rule is its own small function, chained in 'mergeOne', so the
-- precedence logic reads as a pipeline.
module EoJobs.Merge
  ( InboxRecord (..)
  , decodeInboxRecord
  , mergeOne
  , run
  ) where

import Control.Monad (forM, unless, (>=>))
import Data.Bifunctor (first)
import Data.Char (isAsciiLower, isDigit)
import Data.Foldable (traverse_)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.List (sortOn)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day, getZonedTime, localDay, zonedTimeToLocalTime)
import EoJobs.Company
import EoJobs.Db
import EoJobs.Flags (flagAll)
import EoJobs.Json
import EoJobs.StringRules (isBlank, trim, utf16Order)
import System.Directory (doesFileExist, removeFile)

-- | One verified finding about a company. Empty strings are already dropped
-- here for the fields that never overwrite with "".
data InboxRecord = InboxRecord
  { inboxSlug :: Text
  -- ^ Trimmed and canonical.
  , inboxName :: Maybe Text
  , inboxStatus :: Maybe Status
  , inboxWebsite :: Maybe Text
  , inboxCareersUrl :: Maybe Text
  , inboxLocations :: [Text]
  , inboxRemote :: Maybe Text
  , inboxRemoteEvidence :: Maybe Text
  , inboxRemoteConfidence :: Maybe Confidence
  , inboxDescription :: Maybe Text
  , inboxLinks :: [(Text, Text)]
  -- ^ Non-blank links only, in file order.
  , inboxNote :: Maybe Text
  -- ^ Trimmed, non-empty.
  }
  deriving (Eq, Show)

-- | Decode one inbox record. An unknown @status@ or @remote_confidence@ word, a
-- non-canonical slug, or a website, careers URL or web link without a scheme fails.
decodeInboxRecord :: Json -> Either Text InboxRecord
decodeInboxRecord json = do
  pairs <- object json
  let opt :: Text -> Decoder a -> Either Text (Maybe a)
      opt key decode = optionalField key decode pairs
      nonEmpty, trimmedNonEmpty :: Text -> Either Text (Maybe Text)
      nonEmpty key = (>>= nonEmptyText) <$> opt key text
      trimmedNonEmpty key = (>>= nonEmptyText . trim) <$> opt key text
  inboxSlug <- maybe "" trim <$> opt "slug" text
  unless (isCanonicalSlug inboxSlug) $
    Left ("field 'slug': not canonical: " <> inboxSlug)
  inboxName <- trimmedNonEmpty "name"
  inboxStatus <- opt "status" (vocabulary parseStatus)
  inboxWebsite <- nonEmpty "website"
  inboxCareersUrl <- trimmedNonEmpty "careers_url"
  inboxLocations <- fromMaybe [] <$> opt "locations" (list text)
  inboxRemote <- trimmedNonEmpty "remote"
  inboxRemoteEvidence <- nonEmpty "remote_evidence"
  confidenceWord <- opt "remote_confidence" text
  -- a blank word means the agent left it out, not an unknown word
  inboxRemoteConfidence <- traverse (vocabulary parseConfidence . JString) (confidenceWord >>= nonEmptyText . trim)
  inboxDescription <- nonEmpty "description"
  inboxLinks <- maybe [] (mapMaybe nonBlankLink) <$> opt "links" (object >=> traverse (traverse linkValue))
  traverse_ (requireHttpUrl "website") inboxWebsite
  traverse_ (requireHttpUrl "careers_url") inboxCareersUrl
  traverse_ requireWebLink inboxLinks
  inboxNote <- trimmedNonEmpty "note"
  pure InboxRecord {..}
  where
    nonEmptyText t = if T.null t then Nothing else Just t
    linkValue = \case
      JNull -> Right Nothing
      v -> Just <$> text v
    nonBlankLink (key, value) = case value of
      Just v | not (isBlank v) -> Just (key, v)
      _ -> Nothing
    requireHttpUrl key value =
      unless (isHttpUrl value) $ Left ("field '" <> key <> "': no http scheme: " <> value)
    requireWebLink link@(key, value) =
      unless (isWebLink link) $ Left ("field 'links': " <> key <> " has no http scheme: " <> value)

-- | Lowercase ASCII words joined by single hyphens, the form of every company file name.
isCanonicalSlug :: Text -> Bool
isCanonicalSlug slug = all isWord (T.splitOn "-" slug)
  where
    isWord word = not (T.null word) && T.all (\c -> isAsciiLower c || isDigit c) word

-- | Merge an inbox record into the existing company ('Nothing' creates one),
-- tagging a new company with @source@ and stamping notes with @today@.
mergeOne :: Day -> Text -> Maybe Company -> InboxRecord -> Company
mergeOne today source existing record =
  applyNote
    . stampChecked
    . applyLinks
    . setIfPresent record.inboxDescription (\v c -> c {description = v})
    . applyRemote
    . applyLocations
    . applyCareers
    . setIfPresent record.inboxWebsite (\v c -> c {website = v})
    -- a rebrand renames the company in place
    . setIfPresent record.inboxName (\v c -> c {name = v})
    . applyStatus
    $ fromMaybe (newCompany source record) existing
  where
    applyStatus company = case record.inboxStatus of
      -- never downgrade a known status to unknown (e.g. after a fetch failure)
      Just Unknown | company.status /= Unknown -> company
      Just s -> company {status = s}
      Nothing -> company
    -- the finding's URL goes first; a new one replaces the primary board only
    applyCareers company = case record.inboxCareersUrl of
      Nothing -> company
      Just url
        | url `elem` company.careersUrls -> company {careersUrls = url : filter (/= url) company.careersUrls}
        | otherwise -> company {careersUrls = url : drop 1 company.careersUrls}
    applyLocations company
      | null record.inboxLocations = company
      | otherwise = company {locations = flagAll record.inboxLocations}
    applyRemote company = case record.inboxRemote of
      Nothing -> company
      Just value
        -- a finding ranked below the held remote changes nothing; a missing
        -- confidence ranks below every confidence ('Nothing' < 'Just' in 'Ord')
        | not (isBlank company.remote) && record.inboxRemoteConfidence < company.remoteConfidence -> company
        | otherwise ->
            company
              { remote = value
              , remoteEvidence = fromMaybe (if value == company.remote then company.remoteEvidence else "") record.inboxRemoteEvidence
              , remoteConfidence = record.inboxRemoteConfidence
              }
    -- add new links, never clobber an existing one
    applyLinks company = company {links = mergeLinks record.inboxLinks company.links}
    stampChecked company = company {lastChecked = Just (T.pack (show today))}
    applyNote company = case record.inboxNote of
      Nothing -> company
      Just note ->
        let stamp = "[" <> source <> " " <> T.pack (show today) <> "] " <> note
         in company {body = if isBlank company.body then stamp else trim company.body <> "\n\n" <> stamp}

setIfPresent :: Maybe a -> (a -> Company -> Company) -> Company -> Company
setIfPresent value set company = maybe company (`set` company) value

newCompany :: Text -> InboxRecord -> Company
newCompany source record =
  Company
    { name = fromMaybe record.inboxSlug record.inboxName
    , status = Unknown
    , website = ""
    , careersUrls = []
    , locations = []
    , remote = ""
    , remoteEvidence = ""
    , remoteConfidence = Nothing
    , description = ""
    , satellites = ""
    , category = ""
    , listed = False
    , links = []
    , source
    , lastChecked = Nothing
    , companyType = Nothing
    , typeReason = Nothing
    , unlistedReason = Nothing
    , extras = []
    , body = ""
    }

data Outcome = Created Slug | Updated Slug

-- | Merge the inbox's company records into the DB, delete those files, and print
-- a summary. Verdict files stay for classify. Every file is decoded before the
-- first save, so a bad record changes nothing on disk.
run :: Text -> IO ()
run source = do
  today <- localDay . zonedTimeToLocalTime <$> getZonedTime
  files <- listMatching inboxDir (\fileName -> hasExtension ".json" fileName && not (isVerdictFile fileName))
  records <- concat <$> traverse readInboxFile files
  -- sequential on purpose: a later record must see the file an earlier one wrote
  outcomes <- forM records $ \record -> do
    let slug = record.inboxSlug
    exists <- doesFileExist (companyPath slug)
    existing <- if exists then Just <$> readCompany (companyPath slug) else pure Nothing
    save slug (mergeOne today source existing record)
    pure (if exists then Updated slug else Created slug)
  traverse_ removeFile files
  let created = [s | Created s <- outcomes]
      updated = [s | Updated s <- outcomes]
  TIO.putStrLn ("created " <> showT (length created) <> ", updated " <> showT (length updated))
  unless (null updated) $
    TIO.putStrLn ("updated: " <> T.intercalate ", " (sortOn utf16Order updated))
  where
    showT = T.pack . show

-- | Decode one inbox file (a JSON array of records); fails with the file and
-- the index of the first bad record.
readInboxFile :: FilePath -> IO [InboxRecord]
readInboxFile file = do
  json <- readJsonFile file
  items <- either (failAt file) pure (list Right json)
  either (failAt file) pure (traverse decodeAt (zip [0 :: Int ..] items))
  where
    decodeAt (index, item) = first (\e -> "record " <> T.pack (show index) <> ": " <> e) (decodeInboxRecord item)
