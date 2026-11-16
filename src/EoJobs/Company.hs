{-# LANGUAGE NoFieldSelectors #-}

-- | The company record and its closed vocabularies. Parsed once at the file
-- boundary ("EoJobs.Db"), trusted everywhere else.
module EoJobs.Company
  ( Company (..)
  , Slug
  , parseSlug
  , decodeSlug
  , slugText
  , Status (..)
  , statusText
  , parseStatus
  , CompanyType (..)
  , companyTypeText
  , parseCompanyType
  , Confidence (..)
  , confidenceText
  , parseConfidence
  , HttpUrl
  , parseHttpUrl
  , decodeHttpUrl
  , urlText
  , LinkTarget (..)
  , decodeLinkTarget
  , linkTargetText
  , mergeLinks
  ) where

import Data.Char (isAsciiLower, isDigit)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import EoJobs.Json (Json)

-- | A company's file name without @.md@, e.g. @planet-labs@; always canonical.
newtype Slug = Slug Text
  deriving (Eq, Ord, Show)

-- | Lowercase ASCII words joined by single hyphens, the form of every company file name.
parseSlug :: Text -> Maybe Slug
parseSlug raw
  | all isWord (T.splitOn "-" raw) = Just (Slug raw)
  | otherwise = Nothing
  where
    isWord word = not (T.null word) && T.all (\c -> isAsciiLower c || isDigit c) word

-- | 'parseSlug' with an error that names the rejected value.
decodeSlug :: Text -> Either Text Slug
decodeSlug raw = maybe (Left ("not canonical: " <> raw)) Right (parseSlug raw)

slugText :: Slug -> Text
slugText (Slug raw) = raw

-- | An absolute web URL: one that starts with @http://@ or @https://@.
newtype HttpUrl = HttpUrl Text
  deriving (Eq, Ord, Show)

parseHttpUrl :: Text -> Maybe HttpUrl
parseHttpUrl raw
  | any (`T.isPrefixOf` raw) ["http://", "https://"] = Just (HttpUrl raw)
  | otherwise = Nothing

-- | 'parseHttpUrl' with an error that names the rejected value.
decodeHttpUrl :: Text -> Either Text HttpUrl
decodeHttpUrl raw = maybe (Left ("no http scheme: " <> raw)) Right (parseHttpUrl raw)

urlText :: HttpUrl -> Text
urlText (HttpUrl raw) = raw

-- | A @links@ value: a page to link to, or the stock ticker under key @stocks@.
data LinkTarget = WebLink HttpUrl | Ticker Text
  deriving (Eq, Show)

-- | The value of the @links@ entry @key@; only @stocks@ holds a ticker.
decodeLinkTarget :: Text -> Text -> Either Text LinkTarget
decodeLinkTarget "stocks" raw = Right (Ticker raw)
decodeLinkTarget key raw =
  maybe (Left (key <> " has no http scheme: " <> raw)) (Right . WebLink) (parseHttpUrl raw)

-- | The on-disk spelling of a link value.
linkTargetText :: LinkTarget -> Text
linkTargetText = \case
  WebLink url -> urlText url
  Ticker ticker -> ticker

-- | No @Renamed@: a rebrand updates the record in place and stays 'Active'.
data Status = Active | Acquired | Defunct | Unknown
  deriving (Eq, Ord, Show, Enum, Bounded)

data CompanyType = CommercialEo | Consultancy | Reseller | Software | Conglomerate | Nonprofit | NotEo
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | How sure a finding about remote work is; ordered so a merge can refuse to
-- replace a stronger finding with a weaker one.
data Confidence = Low | Medium | High
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | One company file. Every 'Nothing' text or URL field is stored as @""@.
data Company = Company
  { name :: Text
  , status :: Status
  , website :: Maybe HttpUrl
  , careersUrls :: [HttpUrl]
  , locations :: [Text]
  , remote :: Maybe Text
  , remoteEvidence :: Maybe Text
  -- ^ Independent of 'remote': evidence can explain why no remote value was found.
  , remoteConfidence :: Maybe Confidence
  , description :: Maybe Text
  , satellites :: Maybe Text
  , category :: Maybe Text
  , listed :: Bool
  , links :: [(Text, LinkTarget)]
  -- ^ Ordered as on disk, e.g. linkedin before twitter.
  , source :: Text
  , lastChecked :: Maybe Text
  , companyType :: Maybe CompanyType
  , typeReason :: Maybe Text
  , unlistedReason :: Maybe Text
  -- ^ Why the company is deliberately kept off the README; 'Nothing' = eligible.
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
mergeLinks :: [(Text, a)] -> [(Text, a)] -> [(Text, a)]
mergeLinks base winner =
  [(key, fromMaybe baseValue (lookup key winner)) | (key, baseValue) <- base]
    <> [(key, v) | (key, v) <- winner, key `notElem` map fst base]
