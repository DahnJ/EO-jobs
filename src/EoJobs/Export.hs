-- | Build the compact inputs the classification and dedup agents read.
module EoJobs.Export
  ( classInputLine
  , dedupIndexLine
  , classInput
  , dedupIndex
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import EoJobs.Company
import EoJobs.Db
import EoJobs.Json
import EoJobs.Net (regDomain)
import EoJobs.StringRules (isBlank, takeUtf16)

-- | One JSONL line: @{slug,name,desc,body}@, body cut to its first 300 characters.
classInputLine :: Slug -> Company -> Text
classInputLine slug c =
  encodeJson $
    JObject
      [ ("slug", JString slug)
      , ("name", JString c.name)
      , ("desc", JString c.description)
      , ("body", JString (takeUtf16 300 (T.replace "\n" " " c.body)))
      ]

-- | One TSV line: @slug<TAB>name<TAB>domain@.
dedupIndexLine :: Slug -> Company -> Text
dedupIndexLine slug c =
  slug <> "\t" <> c.name <> "\t" <> (if isBlank c.website then "" else regDomain c.website)

-- | Write the classification input to @out@.
classInput :: FilePath -> IO ()
classInput = writeLines classInputLine

-- | Write the dedup index to @out@.
dedupIndex :: FilePath -> IO ()
dedupIndex = writeLines dedupIndexLine

writeLines :: (Slug -> Company -> Text) -> FilePath -> IO ()
writeLines render out = do
  companies <- loadAll
  writeUtf8 out (T.intercalate "\n" (map (uncurry render) companies) <> "\n")
  TIO.putStrLn (T.pack (show (length companies)) <> " companies -> " <> T.pack out)
