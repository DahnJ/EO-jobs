-- | Set each company's type (from agent verdicts in
-- @companies/_inbox/class_*.json@, with a conglomerate override) and derive
-- @listed@ for the README.
module EoJobs.Classify
  ( Verdict (..)
  , decodeVerdicts
  , classifyOne
  , run
  ) where

import Control.Monad (forM, forM_)
import Data.List (isPrefixOf, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import EoJobs.Company
import EoJobs.Db
import EoJobs.Json
import EoJobs.StringRules (utf16Order)

-- | An agent's type decision for one company.
data Verdict = Verdict {verdictType :: CompanyType, verdictReason :: Text}
  deriving (Eq, Show)

-- | Large multi-division parents where EO is one small division: forced override.
conglomerates :: Set.Set Slug
conglomerates =
  Set.fromList
    [ "airbus-space", "airbus-defence-and-space", "trimble", "harris", "gmv"
    , "telespazio", "hexagon-geospatial", "nv5", "merrick", "red-wire-space"
    , "iabg", "l3harris"
    ]

-- | Verdicts by slug from one class file; records without a valid type (or
-- slug) are skipped.
decodeVerdicts :: Json -> Either Text [(Slug, Verdict)]
decodeVerdicts json = catMaybes <$> (list object json >>= traverse verdict)
  where
    verdict pairs = do
      slug <- optionalField "slug" text pairs
      reason <- fromMaybe "" <$> optionalField "reason" text pairs
      pure $ do
        s <- slug
        -- a missing or invalid type skips the verdict instead of failing
        t <- case lookup "type" pairs of
          Just (JString word) -> parseCompanyType word
          _ -> Nothing
        pure (s, Verdict t reason)

-- | Decide the type (override > verdict > existing) and recompute @listed@.
classifyOne :: Map.Map Slug Verdict -> Slug -> Company -> Company
classifyOne verdicts slug company =
  company
    { companyType = Just decidedType
    , typeReason = Just reason
    , listed = decidedType == CommercialEo && company.status == Active && any ("http" `T.isPrefixOf`) company.careersUrls
    }
  where
    (decidedType, reason)
      | slug `Set.member` conglomerates = (Conglomerate, "known large multi-division company")
      | Just v <- Map.lookup slug verdicts = (v.verdictType, v.verdictReason <> " [agent]")
      | otherwise = (fromMaybe CommercialEo company.companyType, fromMaybe "unclassified" company.typeReason)

-- | Apply verdicts to every company, save, and print the type distribution.
run :: IO ()
run = do
  files <- listMatching inboxDir (\n -> "class_" `isPrefixOf` n && hasExtension ".json" n)
  verdictLists <- forM files $ \file -> do
    json <- readJsonFile file
    either (failAt file) pure (decodeVerdicts json)
  let verdicts = Map.fromList (concat verdictLists) -- a later verdict wins
  companies <- loadAll
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
  TIO.putStrLn ("LISTED (commercial-eo + active + has careers): " <> T.pack (show (length (filter (\(_, c) -> c.listed) results))))
  TIO.putStrLn ("\ntype changed vs previous: " <> T.pack (show (length changed)))
  forM_ changed $ \(n, o, t) -> TIO.putStrLn ("  " <> n <> ": " <> o <> " -> " <> t)
