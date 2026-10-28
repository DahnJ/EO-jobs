-- | Merge confirmed duplicate entries from @known_duplicates.json@ into the
-- keeper, union their list and link fields, save the keeper, then delete the
-- dropped files.
-- Re-runnable: a group whose dropped files are already gone is a no-op.
module EoJobs.Dedup
  ( DuplicateGroup (..)
  , decodeGroups
  , absorbDuplicates
  , run
  ) where

import Control.Monad (unless)
import Data.Containers.ListUtils (nubOrd)
import Data.Foldable (traverse_)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import EoJobs.Company
import EoJobs.Db
import EoJobs.Json
import EoJobs.StringRules (isBlank, trim)
import System.Directory (doesFileExist, removeFile)

-- | Slugs confirmed to be one company, and which one survives.
data DuplicateGroup = DuplicateGroup {groupSlugs :: [Slug], keeper :: Slug, reason :: Text}
  deriving (Eq, Show)

decodeGroups :: Json -> Either Text [DuplicateGroup]
decodeGroups = list $ \json -> do
  pairs <- object json
  DuplicateGroup
    <$> field "slugs" (list text) pairs
    <*> field "keep" text pairs
    <*> (fromMaybe "" <$> optionalField "reason" text pairs)

-- | Fold the dropped companies into the keeper (keeper's values win) and note
-- the merge in its body; unchanged when nothing was dropped.
absorbDuplicates :: DuplicateGroup -> Company -> [(Slug, Company)] -> Company
absorbDuplicates _ keeperCompany [] = keeperCompany
absorbDuplicates group keeperCompany dropped =
  withNote (foldl absorb keeperCompany (map snd dropped))
  where
    absorb kept duplicate =
      kept
        { careersUrls = unionInOrder kept.careersUrls duplicate.careersUrls
        , locations = unionInOrder kept.locations duplicate.locations
        , -- keep the keeper's links; add the dropped one's extras
          links = mergeLinks duplicate.links kept.links
        }
    unionInOrder kept extra = kept <> filter (`notElem` kept) extra
    note = "[dedup] merged duplicate(s) " <> T.intercalate ", " (map fst dropped) <> " — " <> group.reason
    withNote c = c {body = if isBlank c.body then note else trim c.body <> "\n\n" <> note}

-- | Apply every group in @known_duplicates.json@ and print what merged.
run :: IO ()
run = do
  json <- readJsonFile duplicatesFile
  groups <- either (failAt duplicatesFile) pure (decodeGroups json)
  merged <- catMaybes <$> traverse foldGroup groups
  TIO.putStrLn ("done: " <> T.pack (show (length merged)) <> " group(s) merged")

duplicatesFile :: FilePath
duplicatesFile = "known_duplicates.json"

foldGroup :: DuplicateGroup -> IO (Maybe Slug)
foldGroup group = do
  keeperExists <- doesFileExist (companyPath group.keeper)
  if not keeperExists
    then do
      TIO.putStrLn ("skip " <> showSlugs group.groupSlugs <> " : keeper " <> group.keeper <> " missing")
      pure Nothing
    else do
      keeperCompany <- readCompany (companyPath group.keeper)
      -- read every dropped file before touching disk, so a bad file loses nothing
      dropped <- catMaybes <$> traverse readDropped (nubOrd group.groupSlugs)
      unless (null dropped) $ do
        save group.keeper (absorbDuplicates group keeperCompany dropped)
        traverse_ (removeFile . companyPath . fst) dropped
        TIO.putStrLn ("merged " <> showSlugs (map fst dropped) <> " -> " <> group.keeper)
      pure (if null dropped then Nothing else Just group.keeper)
  where
    -- a dropped slug still on disk, in group order
    readDropped slug = do
      let path = companyPath slug
      exists <- doesFileExist path
      if slug == group.keeper || not exists
        then pure Nothing
        else Just . (slug,) <$> readCompany path
    showSlugs slugs = encodeJson (JArray (map JString slugs))
