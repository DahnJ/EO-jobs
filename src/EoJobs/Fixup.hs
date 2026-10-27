-- | Idempotent data hygiene: normalize the free-text @remote@ field to
-- canonical values, and backfill a flag emoji on locations lacking one.
module EoJobs.Fixup
  ( FixupResult (..)
  , fixupOne
  , run
  ) where

import Control.Monad (foldM, when)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import EoJobs.Company
import EoJobs.Db
import EoJobs.Flags (flagAll)

remoteCanonical :: Map.Map Text Text
remoteCanonical =
  Map.fromList
    [ ("US based", "Yes (US)"), ("US-based", "Yes (US)"), ("Yes (US-based)", "Yes (US)")
    , ("Yes (US-based?)", "Yes (US)"), ("Yes (~US?)", "Yes (US)"), ("US resident", "Yes (US)")
    , ("Canada-based", "Yes (Canada)"), ("Australia-based", "Yes (Australia)")
    , ("Yes (UK-based?)", "Yes (UK)"), ("Yes (UK-elligible)", "Yes (UK)")
    , ("Yes (France-based?)", "Yes (France)")
    , ("~Yes", "Yes")
    , ("Some roles remote", "Hybrid"), ("Some", "Hybrid"), ("Occasionally", "Hybrid")
    , ("No (Partial)", "Hybrid")
    , ("Maybe", ""), ("?", "")
    , ("No jobs", ""), ("No Jobs", ""), ("None", ""), ("N/A", ""), ("TBD", "")
    , ("Yes (UK, Luxembroug, France, Belgium, Germany)", "Yes (UK, Luxembourg, France, Belgium, Germany)")
    ]

data FixupResult = FixupResult
  { fixed :: Company
  , remoteChanged :: Bool
  , locationsFlagged :: Int
  }
  deriving (Eq, Show)

-- | Normalize one company's @remote@ value and flag its locations.
fixupOne :: Company -> FixupResult
fixupOne company =
  FixupResult
    { fixed = company {remote = remote', locations = locations'}
    , remoteChanged = remote' /= company.remote
    , locationsFlagged = length (filter id (zipWith (/=) company.locations locations'))
    }
  where
    remote' = fromMaybe company.remote (Map.lookup company.remote remoteCanonical)
    locations' = flagAll company.locations

-- | Fix up every company, saving only the changed ones.
run :: IO ()
run = do
  companies <- loadAll
  (remoteCount, flaggedCount) <- foldM step (0 :: Int, 0) companies
  TIO.putStrLn ("remote normalized: " <> showT remoteCount <> "; locations flagged: " <> showT flaggedCount)
  where
    step (remoteCount, flaggedCount) (slug, company) = do
      let result = fixupOne company
      when (result.remoteChanged || result.locationsFlagged > 0) (save slug result.fixed)
      pure (remoteCount + fromEnum result.remoteChanged, flaggedCount + result.locationsFlagged)
    showT = T.pack . show
