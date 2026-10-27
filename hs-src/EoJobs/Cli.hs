-- | Subcommand dispatch, plus the small @stats@ and @flags@ commands.
module EoJobs.Cli
  ( main
  ) where

import Control.Monad (forM, unless, when)
import Data.List (nub, sortOn)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified EoJobs.Classify as Classify
import EoJobs.Company
import EoJobs.Db
import qualified EoJobs.Dedup as Dedup
import qualified EoJobs.Export as Export
import qualified EoJobs.Fixup as Fixup
import EoJobs.Flags (flagAll, hasFlag)
import EoJobs.Json
import qualified EoJobs.Merge as Merge
import qualified EoJobs.Net as Net
import qualified EoJobs.Readme as Readme
import EoJobs.StringRules (utf16Order)
import Options.Applicative
import System.IO (hSetEncoding, stderr, stdout, utf8)

data Command
  = MergeInbox Text
  | ClassifyTypes
  | DedupGroups
  | FixupData
  | BackfillFlags
  | WriteReadme
  | CheckLinks Bool Int
  | CheckRedirects Int
  | Stats
  | ClassInput FilePath
  | DedupIndex FilePath

commandParser :: Parser Command
commandParser =
  hsubparser $
    mconcat
      [ cmd "merge" "Merge verified inbox JSON into the DB" $
          MergeInbox <$> strOption (long "source" <> short 's' <> value "discovery-sweep" <> showDefault <> help "source tag for new files")
      , cmd "classify" "Apply type verdicts and recompute listed" (pure ClassifyTypes)
      , cmd "dedup" "Apply confirmed duplicate merges" (pure DedupGroups)
      , cmd "fixup" "Normalize remote values and backfill location flags" (pure FixupData)
      , cmd "flags" "Backfill location flags" (pure BackfillFlags)
      , cmd "readme" "Rebuild README.md from the DB" (pure WriteReadme)
      , cmd "check-links" "Link-rot sweep over website and careers URLs" $
          CheckLinks
            <$> switch (long "listed-only")
            <*> timeoutOption 8
            <* workersOption
      , cmd "check-redirects" "Find listed sites that redirect to another domain" $
          CheckRedirects <$> timeoutOption 10 <* workersOption
      , cmd "stats" "DB summary" (pure Stats)
      , cmd "class-input" "Write the classification agent's JSONL input" $
          ClassInput <$> outOption "/tmp/class_in.jsonl"
      , cmd "dedup-index" "Write the dedup agent's TSV index" $
          DedupIndex <$> outOption "/tmp/company_index.tsv"
      ]
  where
    cmd name desc parser = command name (info parser (progDesc desc))
    timeoutOption d = option auto (long "timeout" <> metavar "SECS" <> value d <> showDefault)
    -- accepted for compatibility; one green thread per URL needs no pool size
    workersOption = option auto (long "workers" <> metavar "N" <> value (16 :: Int) <> showDefault)
    outOption d = strOption (long "out" <> metavar "PATH" <> value d <> showDefault)

dispatch :: Command -> IO ()
dispatch = \case
  MergeInbox source -> Merge.run source
  ClassifyTypes -> Classify.run
  DedupGroups -> Dedup.run
  FixupData -> Fixup.run
  BackfillFlags -> backfillFlags
  WriteReadme -> Readme.run
  CheckLinks listedOnly timeoutSeconds -> Net.checkLinks listedOnly timeoutSeconds
  CheckRedirects timeoutSeconds -> Net.checkRedirects timeoutSeconds
  Stats -> stats
  ClassInput out -> Export.classInput out
  DedupIndex out -> Export.dedupIndex out

-- | Entry point of the @eojobs@ executable.
main :: IO ()
main = do
  mapM_ (`hSetEncoding` utf8) [stdout, stderr]
  dispatch =<< execParser (info (commandParser <**> helper) (progDesc "EO-jobs deterministic pipeline"))

stats :: IO ()
stats = do
  companies <- map snd <$> loadAll
  TIO.putStrLn ("loaded " <> showT (length companies) <> " companies")
  TIO.putStrLn ("by status: " <> frequencies (map (statusText . (.status)) companies))
  TIO.putStrLn ("by source: " <> frequencies (map (.source) companies))
  TIO.putStrLn ("listed (README candidates): " <> showT (length (filter (.listed) companies)))

-- | Counts per value as a JSON object, keys sorted.
frequencies :: [Text] -> Text
frequencies values =
  encodeJson (JObject [(k, JNumber (IntegerNumber n)) | (k, n) <- Map.toList (Map.fromListWith (+) [(v, 1) | v <- values])])

-- | Backfill flags across the DB and report locations no rule matched.
backfillFlags :: IO ()
backfillFlags = do
  companies <- loadAll
  results <- forM companies $ \(slug, company) -> do
    let flagged = flagAll company.locations
    when (flagged /= company.locations) (save slug company {locations = flagged})
    pure (length (filter id (zipWith (/=) company.locations flagged)), filter (not . hasFlag) flagged)
  let fixedCount = sum (map fst results)
      misses = sortOn utf16Order (nub (concatMap snd results))
  TIO.putStrLn ("flagged " <> showT fixedCount <> " locations; still unflagged: " <> showT (length misses))
  unless (null misses) (TIO.putStrLn ("unmatched: " <> encodeJson (JArray (map JString misses))))

showT :: Show a => a -> Text
showT = T.pack . show
