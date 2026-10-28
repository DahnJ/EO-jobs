{-# LANGUAGE NoFieldSelectors #-}

-- | The company record and its closed vocabularies. Parsed once at the file
-- boundary ("EoJobs.Db"), trusted everywhere else.
module EoJobs.Company
  ( Company (..)
  , Slug
  , Status (..)
  , statusText
  , parseStatus
  , CompanyType (..)
  , companyTypeText
  , parseCompanyType
  , Confidence (..)
  , confidenceText
  , parseConfidence
  , mergeLinks
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import EoJobs.Json (Json)

-- | A company's file name without @.md@, e.g. @planet-labs@.
type Slug = Text

-- | No @Renamed@: a rebrand updates the record in place and stays 'Active'.
data Status = Active | Acquired | Defunct | Unknown
  deriving (Eq, Ord, Show, Enum, Bounded)

data CompanyType = CommercialEo | Consultancy | Reseller | Software | Conglomerate | Nonprofit | NotEo
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | How sure a finding about remote work is; ordered so a merge can refuse to
-- replace a stronger finding with a weaker one.
data Confidence = Low | Medium | High
  deriving (Eq, Ord, Show, Enum, Bounded)

data Company = Company
  { name :: Text
  , status :: Status
  , website :: Text
  , careersUrls :: [Text]
  , locations :: [Text]
  , remote :: Text
  , remoteEvidence :: Text
  , remoteConfidence :: Maybe Confidence
  , description :: Text
  , satellites :: Text
  , category :: Text
  , listed :: Bool
  , links :: [(Text, Text)]
  -- ^ Ordered as on disk, e.g. linkedin before twitter.
  , source :: Text
  , lastChecked :: Maybe Text
  , companyType :: Maybe CompanyType
  , typeReason :: Maybe Text
  , extras :: [(Text, Json)]
  -- ^ Unknown frontmatter keys (snake_case), kept so a rewrite loses nothing.
  , body :: Text
  }
  deriving (Eq, Show)

-- | The on-disk spelling, e.g. @"active"@.
statusText :: Status -> Text
statusText = \case
  Active -> "active"
  Acquired -> "acquired"
  Defunct -> "defunct"
  Unknown -> "unknown"

parseStatus :: Text -> Maybe Status
parseStatus = parseEnum statusText

-- | The on-disk spelling, e.g. @"commercial-eo"@.
companyTypeText :: CompanyType -> Text
companyTypeText = \case
  CommercialEo -> "commercial-eo"
  Consultancy -> "consultancy"
  Reseller -> "reseller"
  Software -> "software"
  Conglomerate -> "conglomerate"
  Nonprofit -> "nonprofit"
  NotEo -> "not-eo"

parseCompanyType :: Text -> Maybe CompanyType
parseCompanyType = parseEnum companyTypeText

-- | The on-disk spelling, e.g. @"high"@.
confidenceText :: Confidence -> Text
confidenceText = \case
  Low -> "low"
  Medium -> "medium"
  High -> "high"

parseConfidence :: Text -> Maybe Confidence
parseConfidence = parseEnum confidenceText

parseEnum :: (Enum a, Bounded a) => (a -> Text) -> Text -> Maybe a
parseEnum render raw = lookup raw [(render v, v) | v <- [minBound .. maxBound]]

-- | Merge two ordered link maps: @base@'s keys first, in order, with @winner@'s
-- value where both have the key, then @winner@'s other keys in order.
mergeLinks :: [(Text, Text)] -> [(Text, Text)] -> [(Text, Text)]
mergeLinks base winner =
  [(key, fromMaybe baseValue (lookup key winner)) | (key, baseValue) <- base]
    <> [(key, v) | (key, v) <- winner, key `notElem` map fst base]
