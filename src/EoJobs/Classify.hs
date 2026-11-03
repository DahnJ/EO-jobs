-- | Set each company's type and @unlisted_reason@ (from agent verdicts in
-- @companies/_inbox/class_*.json@) and derive @listed@ for the README: a company
-- is listed if it does EO work and hires for it, whatever its type.
module EoJobs.Classify
  ( Verdict (..)
  , decodeVerdicts
  , classifyOne
  , run
  ) where

import Control.Monad (forM, forM_, mfilter, unless, (>=>))
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import EoJobs.Company
import EoJobs.Db
import EoJobs.Json
import EoJobs.StringRules (isBlank, utf16Order)

-- | An agent's decision for one company.
data Verdict = Verdict
  { verdictType :: CompanyType
  , verdictReason :: Text
  , verdictUnlistedReason :: Maybe Text
  }
  deriving (Eq, Show)

-- | Verdicts by slug from one class file; a missing slug or an invalid type fails.
decodeVerdicts :: Json -> Either Text [(Slug, Verdict)]
decodeVerdicts = list (object >=> verdict)
  where
    verdict pairs = do
      slug <- field "slug" text pairs
      verdictType <- field "type" (vocabulary parseCompanyType) pairs
      reason <- fromMaybe "" <$> optionalField "reason" text pairs
      unlistedReason <- mfilter (not . isBlank) <$> optionalField "unlisted_reason" text pairs
      pure (slug, Verdict verdictType reason unlistedReason)

-- | Apply the company's verdict, if any, and recompute @listed@. A verdict
-- replaces the stored type and @unlisted_reason@, including clearing the latter.
classifyOne :: Map.Map Slug Verdict -> Slug -> Company -> Company
classifyOne verdicts slug company = decided {listed = isListed decided}
  where
    decided = case Map.lookup slug verdicts of
      Just v ->
        company
          { companyType = Just v.verdictType
          , typeReason = Just (v.verdictReason <> " [agent]")
          , unlistedReason = v.verdictUnlistedReason
          }
      Nothing -> company

-- | Classified as doing EO work, reachable through a careers link, and not kept off on purpose.
isListed :: Company -> Bool
isListed company =
  maybe False (/= NotEo) company.companyType
    && company.status == Active
    && any isHttpUrl company.careersUrls
    && isNothing company.unlistedReason

-- | Apply verdicts to every company, save, and print the type distribution.
run :: IO ()
run = do
  files <- listMatching inboxDir isVerdictFile
  verdictLists <- forM files $ \file -> do
    json <- readJsonFile file
    either (failAt file) pure (decodeVerdicts json)
  let verdicts = Map.fromList (concat verdictLists) -- a later verdict wins
  companies <- loadAll
  let unknownSlugs = filter (`notElem` map fst companies) (Map.keys verdicts)
  unless (null unknownSlugs) $
    failAt inboxDir ("verdict for unknown slug: " <> T.intercalate ", " unknownSlugs)
  results <- forM companies $ \(slug, company) -> do
    let classified = classifyOne verdicts slug company
    save slug classified
    pure (company, classified)
  let typeOf c = maybe "" companyTypeText c.companyType
      counts = Map.toList (Map.fromListWith (+) [(typeOf c, 1 :: Integer) | (_, c) <- results])
      changed =
        sortOn (\(n, o, t) -> (utf16Order n, utf16Order o, utf16Order t))
          [ (new.name, companyTypeText old, typeOf new)
          | (original, new) <- results
          , Just old <- [original.companyType]
          , Just old /= new.companyType
          ]
  TIO.putStrLn ("type distribution: " <> encodeJson (JObject [(k, JNumber (IntegerNumber n)) | (k, n) <- counts]))
  TIO.putStrLn ("LISTED (type not not-eo + active + has careers + no unlisted_reason): " <> T.pack (show (length (filter (\(_, c) -> c.listed) results))))
  let unclassified = [slug | (slug, company) <- companies, isNothing (classifyOne verdicts slug company).companyType]
  unless (null unclassified) $
    TIO.putStrLn ("unclassified, so not listed: " <> T.intercalate ", " unclassified)
  TIO.putStrLn ("\ntype changed vs previous: " <> T.pack (show (length changed)))
  forM_ changed $ \(n, o, t) -> TIO.putStrLn ("  " <> n <> ": " <> o <> " -> " <> t)
