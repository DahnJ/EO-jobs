-- | The only module that knows the on-disk format. A company file is @---@,
-- one @key: <json>@ line per field, @---@, a blank line, then free text.
-- Everywhere else a company is a typed 'Company'.
module EoJobs.Db
  ( dbDir
  , inboxDir
  , parseCompany
  , renderCompany
  , companyPath
  , listMatching
  , readCompany
  , loadAll
  , save
  , readUtf8
  , writeUtf8
  , readJsonFile
  , hasExtension
  , failAt
  ) where

import Control.Monad (unless, (>=>))
import qualified Data.ByteString as BS
import Data.Bifunctor (first)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import EoJobs.Company
import EoJobs.StringRules (isBlank, utf16Order, trim)
import EoJobs.Json
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeFileName, (</>))

dbDir :: FilePath
dbDir = "companies"

inboxDir :: FilePath
inboxDir = "companies/_inbox"

-- | Field order on disk; unknown keys follow, sorted.
knownKeys :: [Text]
knownKeys =
  [ "name", "status", "website", "careers_urls", "locations", "remote", "remote_evidence"
  , "remote_confidence", "description", "satellites", "category", "listed", "links"
  , "source", "last_checked", "type", "type_reason"
  ]

-- | Parse a company file's text; the error says which field is wrong.
parseCompany :: Text -> Either Text Company
parseCompany fileText = do
  unless ("---" `T.isPrefixOf` fileText) (Left "missing frontmatter")
  let (frontmatter, afterFrontmatter) = T.breakOn "---" (T.drop 3 fileText)
      lines' = filter (not . isBlank) (splitLines (trim frontmatter))
  pairs <- traverse parseLine lines'
  -- a repeated key keeps its last value, as Clojure's `into {}` does
  decodeCompany (Map.fromList pairs) (trim (T.drop 3 afterFrontmatter))
  where
    splitLines = map (T.dropWhileEnd (== '\r')) . T.splitOn "\n"
    parseLine line = case T.breakOn ": " line of
      (_, "") -> Left ("frontmatter line without ': ': " <> line)
      (key, rest) -> do
        parsed <- first (\e -> "field '" <> key <> "': " <> e) (parseJson (T.drop 2 rest))
        -- Clojure keywordizes `a-b` and `a_b` to the same key and writes `a_b`
        pure (T.replace "-" "_" key, parsed)

decodeCompany :: Map.Map Text Json -> Text -> Either Text Company
decodeCompany fields bodyText = do
  name <- required "name" text
  status <- required "status" (vocabulary parseStatus)
  website <- required "website" text
  careersUrls <- required "careers_urls" (list text)
  locations <- required "locations" (list text)
  remote <- required "remote" text
  remoteEvidence <- required "remote_evidence" text
  remoteConfidence <- optional' "remote_confidence" (vocabulary parseConfidence)
  description <- required "description" text
  satellites <- required "satellites" text
  category <- required "category" text
  listed <- required "listed" bool
  links <- required "links" (object >=> traverse (traverse text))
  source <- required "source" text
  lastChecked <- optional' "last_checked" text
  companyType <- optional' "type" (vocabulary parseCompanyType)
  typeReason <- optional' "type_reason" text
  pure
    Company
      { name, status, website, careersUrls, locations, remote, remoteEvidence, remoteConfidence
      , description, satellites, category, listed, links, source, lastChecked, companyType
      , typeReason, extras, body = bodyText
      }
  where
    pairs = Map.toList fields
    required :: Text -> Decoder a -> Either Text a
    required key decode = field key decode pairs
    optional' :: Text -> Decoder a -> Either Text (Maybe a)
    optional' key decode = optionalField key decode pairs
    extras =
      sortOn (utf16Order . T.replace "_" "-" . fst)
        (Map.toList (Map.withoutKeys fields (Set.fromList knownKeys)))

-- | Serialize a company back to file text.
renderCompany :: Company -> Text
renderCompany company =
  if isBlank company.body then header else header <> "\n" <> trim company.body <> "\n"
  where
    header = T.intercalate "\n" (["---"] <> map renderLine fields <> ["---"]) <> "\n"
    renderLine (key, value) = key <> ": " <> encodeJson value
    string = JString
    strings = JArray . map JString
    fields =
      [ ("name", string company.name)
      , ("status", string (statusText company.status))
      , ("website", string company.website)
      , ("careers_urls", strings company.careersUrls)
      , ("locations", strings company.locations)
      , ("remote", string company.remote)
      , ("remote_evidence", string company.remoteEvidence)
      ]
        <> [("remote_confidence", string (confidenceText c)) | Just c <- [company.remoteConfidence]]
        <> [ ("description", string company.description)
           , ("satellites", string company.satellites)
           , ("category", string company.category)
           , ("listed", JBool company.listed)
           , ("links", JObject [(k, JString v) | (k, v) <- company.links])
           , ("source", string company.source)
           ]
        <> [("last_checked", string d) | Just d <- [company.lastChecked]]
        <> [("type", string (companyTypeText t)) | Just t <- [company.companyType]]
        <> [("type_reason", string r) | Just r <- [company.typeReason]]
        <> company.extras

companyPath :: Slug -> FilePath
companyPath slug = dbDir </> T.unpack slug <> ".md"

-- | Paths in @dir@ whose file name passes @keep@, sorted by name; a missing
-- directory has no files.
listMatching :: FilePath -> (String -> Bool) -> IO [FilePath]
listMatching dir keep = do
  exists <- doesDirectoryExist dir
  names <- if exists then listDirectory dir else pure []
  pure [dir </> n | n <- sortOn (utf16Order . T.pack) names, keep n]

-- | Read and parse one company file; fails with the path and the bad field.
readCompany :: FilePath -> IO Company
readCompany path = do
  contents <- readUtf8 path
  either (failAt path) pure (parseCompany contents)

-- | Every company as @(slug, company)@, ordered by slug.
loadAll :: IO [(Slug, Company)]
loadAll = do
  paths <- listMatching dbDir (hasExtension ".md")
  traverse (\p -> (slugOf p,) <$> readCompany p) paths
  where
    slugOf p = let n = T.pack (takeFileName p) in fromMaybe n (T.stripSuffix ".md" n)

save :: Slug -> Company -> IO ()
save slug company = writeUtf8 (companyPath slug) (renderCompany company)

-- | Read a UTF-8 file; invalid UTF-8 fails with the path instead of being replaced.
readUtf8 :: FilePath -> IO Text
readUtf8 path = do
  bytes <- BS.readFile path
  either (failAt path . ("invalid UTF-8: " <>) . T.pack . show) pure (decodeUtf8' bytes)

writeUtf8 :: FilePath -> Text -> IO ()
writeUtf8 path = BS.writeFile path . encodeUtf8

-- | Read and parse a JSON file; fails with the path.
readJsonFile :: FilePath -> IO Json
readJsonFile path = do
  contents <- readUtf8 path
  either (failAt path) pure (parseJson contents)

-- | Whether a file name ends with @suffix@, e.g. @hasExtension ".json"@.
hasExtension :: String -> String -> Bool
hasExtension suffix fileName = T.pack suffix `T.isSuffixOf` T.pack fileName

-- | Fail with the path that caused the error, e.g. @companies/acme.md: missing field 'status'@.
failAt :: FilePath -> Text -> IO a
failAt path message = ioError (userError (path <> ": " <> T.unpack message))
