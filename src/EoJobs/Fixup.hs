-- | Idempotent data hygiene: normalize the free-text @remote@ field to
-- canonical values, and backfill a flag emoji on locations lacking one.
module EoJobs.Fixup
  ( FixupResult (..)
  , fixupOne
  , run
  ) where

import Control.Monad (foldM, when)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import EoJobs.Company
import EoJobs.Db
import EoJobs.Flags (flagAll)

-- | Canonical replacements for free-text remote values; 'Nothing' clears one.
remoteCanonical :: Map.Map Text (Maybe Text)
remoteCanonical =
  Map.fromList
    [ ("US based", Just "Yes (US)"), ("US-based", Just "Yes (US)"), ("Yes (US-based)", Just "Yes (US)")
    , ("Yes (US-based?)", Just "Yes (US)"), ("Yes (~US?)", Just "Yes (US)"), ("US resident", Just "Yes (US)")
    , ("Canada-based", Just "Yes (Canada)"), ("Australia-based", Just "Yes (Australia)")
    , ("Yes (UK-based?)", Just "Yes (UK)"), ("Yes (UK-elligible)", Just "Yes (UK)")
    , ("Yes (France-based?)", Just "Yes (France)")
    , ("~Yes", Just "Yes")
    , ("Some roles remote", Just "Hybrid"), ("Some", Just "Hybrid"), ("Occasionally", Just "Hybrid")
    , ("No (Partial)", Just "Hybrid")
    , ("Maybe", Nothing), ("?", Nothing)
    , ("No jobs", Nothing), ("No Jobs", Nothing), ("None", Nothing), ("N/A", Nothing), ("TBD", Nothing)
    , ("Yes (UK, Luxembroug, France, Belgium, Germany)", Just "Yes (UK, Luxembourg, France, Belgium, Germany)")
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
    remote' = company.remote >>= \value -> Map.findWithDefault (Just value) value remoteCanonical
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
