{-# LANGUAGE RecordWildCards #-}

-- | Apply verified inbox records (@companies/_inbox/*.json@) into the DB. Each
-- per-field rule is its own small function, chained in 'mergeOne', so the
-- precedence logic reads as a pipeline.
module EoJobs.Merge
  ( InboxRecord (..)
  , decodeInboxRecord
  , mergeOne
  , run
  ) where

import Control.Monad (forM, unless, (>=>))
import Data.Maybe (fromMaybe, mapMaybe)
import Data.List (sortOn)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day, getZonedTime, localDay, zonedTimeToLocalTime)
import EoJobs.Company
import EoJobs.Db
import EoJobs.Flags (flagAll)
import EoJobs.Json
import EoJobs.StringRules (isBlank, trim, utf16Order)
import System.Directory (doesFileExist)

-- | One verified finding about a company. Empty strings are already dropped
-- here for the fields that never overwrite with "".
data InboxRecord = InboxRecord
  { inboxSlug :: Text
  -- ^ Trimmed; empty means the record is skipped.
  , inboxName :: Maybe Text
  , inboxStatus :: Maybe Status
  , inboxWebsite :: Maybe Text
  , inboxCareersUrl :: Maybe Text
  , inboxLocations :: [Text]
  , inboxRemote :: Maybe Text
  , inboxRemoteEvidence :: Maybe Text
  , inboxRemoteConfidence :: Maybe Confidence
  , inboxDescription :: Maybe Text
  , inboxLinks :: [(Text, Text)]
  -- ^ Non-blank links only, in file order.
  , inboxNote :: Maybe Text
  -- ^ Trimmed, non-empty.
  }
  deriving (Eq, Show)

-- | Decode one inbox record; an unknown @status@ or @remote_confidence@ word fails.
decodeInboxRecord :: Json -> Either Text InboxRecord
decodeInboxRecord json = do
  pairs <- object json
  let opt :: Text -> Decoder a -> Either Text (Maybe a)
      opt key decode = optionalField key decode pairs
      nonEmpty, trimmedNonEmpty :: Text -> Either Text (Maybe Text)
      nonEmpty key = (>>= nonEmptyText) <$> opt key text
      trimmedNonEmpty key = (>>= nonEmptyText . trim) <$> opt key text
  inboxSlug <- maybe "" trim <$> opt "slug" text
  inboxName <- opt "name" text
  inboxStatus <- opt "status" (vocabulary parseStatus)
  inboxWebsite <- nonEmpty "website"
  inboxCareersUrl <- trimmedNonEmpty "careers_url"
  inboxLocations <- fromMaybe [] <$> opt "locations" (list text)
  inboxRemote <- nonEmpty "remote"
  inboxRemoteEvidence <- nonEmpty "remote_evidence"
  confidenceWord <- opt "remote_confidence" text
  -- "" means the agent left it blank, not an unknown word
  inboxRemoteConfidence <- traverse (vocabulary parseConfidence . JString) (confidenceWord >>= nonEmptyText)
  inboxDescription <- nonEmpty "description"
  inboxLinks <- maybe [] (mapMaybe nonBlankLink) <$> opt "links" (object >=> traverse (traverse linkValue))
  inboxNote <- trimmedNonEmpty "note"
  pure InboxRecord {..}
  where
    nonEmptyText t = if T.null t then Nothing else Just t
    linkValue = \case
      JNull -> Right Nothing
      v -> Just <$> text v
    nonBlankLink (key, value) = case value of
      Just v | not (isBlank v) -> Just (key, v)
      _ -> Nothing

-- | Merge an inbox record into the existing company ('Nothing' creates one),
-- tagging a new company with @source@ and stamping notes with @today@.
mergeOne :: Day -> Text -> Maybe Company -> InboxRecord -> Company
mergeOne today source existing record =
  applyNote
    . stampChecked
    . applyLinks
    . setIfPresent record.inboxDescription (\v c -> c {description = v})
    . applyRemote
    . applyLocations
    . applyCareers
    . setIfPresent record.inboxWebsite (\v c -> c {website = v})
    . applyStatus
    $ fromMaybe (newCompany source record) existing
  where
    applyStatus company = case record.inboxStatus of
      -- never downgrade a known status to unknown (e.g. after a fetch failure)
      Just Unknown | company.status /= Unknown -> company
      Just s -> company {status = s}
      Nothing -> company
    applyCareers company = maybe company (\url -> company {careersUrls = [url]}) record.inboxCareersUrl
    applyLocations company
      | null record.inboxLocations = company
      | otherwise = company {locations = flagAll record.inboxLocations}
    applyRemote company
      -- a lower-confidence remote finding never overwrites a higher one
      | Just incoming <- record.inboxRemoteConfidence
      , Just held <- company.remoteConfidence
      , incoming < held =
          company
      | otherwise =
          setIfPresent record.inboxRemoteConfidence (\v c -> c {remoteConfidence = Just v})
            . setIfPresent record.inboxRemoteEvidence (\v c -> c {remoteEvidence = v})
            . setIfPresent record.inboxRemote (\v c -> c {remote = v})
            $ company
    -- add new links, never clobber an existing one
    applyLinks company = company {links = mergeLinks record.inboxLinks company.links}
    stampChecked company = company {lastChecked = Just (T.pack (show today))}
    applyNote company = case record.inboxNote of
      Nothing -> company
      Just note ->
        let stamp = "[" <> source <> " " <> T.pack (show today) <> "] " <> note
         in company {body = if isBlank company.body then stamp else trim company.body <> "\n\n" <> stamp}

setIfPresent :: Maybe a -> (a -> Company -> Company) -> Company -> Company
setIfPresent value set company = maybe company (`set` company) value

newCompany :: Text -> InboxRecord -> Company
newCompany source record =
  Company
    { name = fromMaybe record.inboxSlug record.inboxName
    , status = Unknown
    , website = ""
    , careersUrls = []
    , locations = []
    , remote = ""
    , remoteEvidence = ""
    , remoteConfidence = Nothing
    , description = ""
    , satellites = ""
    , category = ""
    , listed = False
    , links = []
    , source
    , lastChecked = Nothing
    , companyType = Nothing
    , typeReason = Nothing
    , extras = []
    , body = ""
    }

data Outcome = Created Slug | Updated Slug | Skipped Text

-- | Merge every inbox file into the DB and print a summary.
run :: Text -> IO ()
run source = do
  today <- localDay . zonedTimeToLocalTime <$> getZonedTime
  files <- listMatching inboxDir (hasExtension ".json")
  outcomes <- fmap concat . forM files $ \file -> do
    json <- readJsonFile file
    records <- either (failAt file) pure (list decodeInboxRecord json)
    -- sequential on purpose: a later record must see the file an earlier one wrote
    forM records $ \record ->
      if T.null record.inboxSlug
        then pure (Skipped (fromMaybe "?" record.inboxName))
        else do
          let slug = record.inboxSlug
          exists <- doesFileExist (companyPath slug)
          existing <- if exists then Just <$> readCompany (companyPath slug) else pure Nothing
          save slug (mergeOne today source existing record)
          pure (if exists then Updated slug else Created slug)
  let created = [s | Created s <- outcomes]
      updated = [s | Updated s <- outcomes]
      skipped = [n | Skipped n <- outcomes]
  TIO.putStrLn
    ( "created " <> showT (length created) <> ", updated " <> showT (length updated)
        <> ", skipped " <> showT (length skipped)
    )
  unless (null updated) $
    TIO.putStrLn ("updated: " <> T.intercalate ", " (sortOn utf16Order updated))
  unless (null skipped) $
    TIO.putStrLn ("skipped (no slug): " <> T.intercalate ", " skipped)
  where
    showT = T.pack . show
