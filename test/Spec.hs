module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (forM_)
import qualified Data.ByteString as BS
import Data.Either (isLeft)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (fromGregorian)
import EoJobs.Classify (Verdict (..), classifyOne, decodeVerdicts)
import EoJobs.Company
import EoJobs.Db (hasExtension, listMatching, parseCompany, readUtf8, renderCompany, writeUtf8)
import EoJobs.Export (classInputLine)
import EoJobs.Fixup (FixupResult (..), fixupOne)
import EoJobs.Flags (addFlag)
import EoJobs.Json
import EoJobs.Merge (InboxRecord (..), decodeInboxRecord, mergeOne)
import qualified EoJobs.Merge as Merge
import qualified EoJobs.Classify as Classify
import qualified EoJobs.Dedup as Dedup
import EoJobs.Net (introLinks, isAliveStatus, regDomain)
import EoJobs.Readme (renderReadme)
import System.Directory (createDirectoryIfMissing, doesFileExist, getTemporaryDirectory, removePathForcibly, withCurrentDirectory)
import System.FilePath ((</>))
import Test.Hspec

main :: IO ()
main = hspec $ do
  describe "company files" $ do
    it "parse then render reproduces every file byte-for-byte" $ do
      -- Arrange
      paths <- listMatching "companies" (hasExtension ".md")
      -- Act
      mismatches <- fmap concat . traverse roundTripMismatch $ paths
      -- Assert
      length paths `shouldSatisfy` (> 600)
      mismatches `shouldBe` []

    it "renders README.md byte-identical to the committed one" $ do
      -- Arrange
      paths <- listMatching "companies" (hasExtension ".md")
      companies <- traverse (fmap (either (error . T.unpack) id . parseCompany) . readUtf8) paths
      intro <- readUtf8 "intro.md"
      expected <- readUtf8 "README.md"
      -- Act
      let rendered = renderReadme intro companies
      -- Assert
      rendered `shouldBe` expected

    it "stores every link except a stocks ticker with an http scheme" $ do
      -- Arrange
      paths <- listMatching "companies" (hasExtension ".md")
      -- Act
      companies <- traverse (fmap (either (error . T.unpack) id . parseCompany) . readUtf8) paths
      let schemeless = [link | c <- companies, link <- c.links, not (isWebLink link)]
      -- Assert
      schemeless `shouldBe` []

    it "ends the frontmatter only at a line that is exactly ---" $ do
      -- Arrange
      let withDashes = T.replace "\"Satellite analytics.\"" "\"SAR --- optical\"" sampleFile <> "\nbody\n---\nmore\n"
      -- Act
      let parsed = parseCompany withDashes
      -- Assert
      fmap (\c -> (c.description, c.body)) parsed `shouldBe` Right ("SAR --- optical", "body\n---\nmore")
      fmap renderCompany parsed `shouldBe` Right withDashes

    it "round-trips unlisted_reason right after type_reason" $ do
      -- Arrange
      let withReason =
            T.replace
              "type_reason: \"makes EO products\"\n"
              "type_reason: \"makes EO products\"\nunlisted_reason: \"no EO roles\"\n"
              sampleFile
      -- Act
      let parsed = parseCompany withReason
      -- Assert
      fmap (.unlistedReason) parsed `shouldBe` Right (Just "no EO roles")
      fmap renderCompany parsed `shouldBe` Right withReason

    it "fails with the field name when a required field is missing" $ do
      -- Arrange
      let withoutStatus = T.unlines (filter (not . ("status:" `T.isPrefixOf`)) (T.lines sampleFile))
      -- Act
      let result = parseCompany withoutStatus
      -- Assert
      result `shouldBe` Left "missing field 'status'"

  describe "renderReadme" $ do
    it "shows only the name in the name cell, whatever the type" $ do
      -- Arrange
      let company = sampleCompany {companyType = Just Conglomerate}
      -- Act
      let rendered = renderReadme "" [company]
      -- Assert
      rendered `shouldSatisfy` T.isInfixOf "| <a href=\"https://acme.io\">Acme EO</a> | "

  describe "readUtf8" $ do
    it "fails naming the file when its bytes are not UTF-8" $ inScratchDir "utf8" $ do
      -- Arrange
      BS.writeFile "bad.md" (BS.pack [0x61, 0xFF, 0x62])
      -- Act
      failure <- failureMessage (readUtf8 "bad.md")
      -- Assert
      failure `shouldSatisfy` maybe False ("bad.md: invalid UTF-8" `isInfixOf`)

  describe "encodeJson" $ do
    it "escapes only quotes, backslashes and control characters" $ do
      -- Arrange
      let value = JString "a\"b\\c/d\n\t\x01 é 🌍"
      -- Act
      let encoded = encodeJson value
      -- Assert
      encoded `shouldBe` "\"a\\\"b\\\\c/d\\n\\t\\u0001 é 🌍\""

    it "writes compact arrays and objects in key order" $ do
      -- Arrange
      let value = JObject [("z", JArray [JString "x", JString "y"]), ("a", JBool True), ("n", JNull)]
      -- Act
      let encoded = encodeJson value
      -- Assert
      encoded `shouldBe` "{\"z\":[\"x\",\"y\"],\"a\":true,\"n\":null}"

    it "round-trips parsed objects without reordering keys" $ do
      -- Arrange
      let source = "{\"linkedin\":\"l\",\"twitter\":\"t\",\"crunchbase\":\"c\"}"
      -- Act
      let reEncoded = encodeJson <$> parseJson source
      -- Assert
      reEncoded `shouldBe` Right source

  describe "addFlag" $ do
    let cases =
          [ ("London", "🇬🇧 London")
          , ("Paris, France", "🇫🇷 Paris, France")
          , ("Austin, TX", "🇺🇸 Austin, TX")
          , ("Remote", "🌐 Remote")
          , ("Remote (Europe)", "🌍 Remote (Europe)")
          , ("Asia Pacific, Global", "🌏 Asia Pacific, Global")
          , ("Greater London Area", "🇬🇧 Greater London Area")
          , ("🇩🇪 Berlin", "🇩🇪 Berlin")
          , ("Indianapolis, Indiana", "🇺🇸 Indianapolis, Indiana")
          , ("Albuquerque, New Mexico", "🇺🇸 Albuquerque, New Mexico")
          , ("Santa Fe New Mexico", "🇺🇸 Santa Fe New Mexico")
          , ("Atlanta, Georgia", "🇺🇸 Atlanta, Georgia")
          , ("Tbilisi, Georgia", "🇬🇪 Tbilisi, Georgia")
          , ("Perth, WA", "🇦🇺 Perth, WA")
          , ("Vancouver, CA", "🇨🇦 Vancouver, CA")
          , ("Seattle, WA", "🇺🇸 Seattle, WA")
          , ("Sacramento, CA", "🇺🇸 Sacramento, CA")
          , ("Cambridge, MA", "🇺🇸 Cambridge, MA")
          , ("Cambridge, Massachusetts", "🇺🇸 Cambridge, Massachusetts")
          , ("Indianapolis", "Indianapolis")
          , ("Georgia", "Georgia")
          , ("Atlantis", "Atlantis")
          , ("   ", "   ")
          ]
    forM_ cases $ \(input, expected) ->
      it ("flags " <> show input) $ do
        -- Arrange (the case table above)
        -- Act
        let flagged = addFlag input
        -- Assert
        flagged `shouldBe` expected

  describe "mergeOne" $ do
    let today = fromGregorian 2026 10 27

    it "never downgrades a known status to unknown" $ do
      -- Arrange
      let record = inbox [("slug", JString "acme"), ("status", JString "unknown")]
      -- Act
      let merged = mergeOne today "sweep" (Just sampleCompany) record
      -- Assert
      merged.status `shouldBe` Active

    it "does not let a lower-confidence remote finding overwrite a higher one" $ do
      -- Arrange
      let existing = sampleCompany {remote = "Yes", remoteConfidence = Just High}
          record = inbox [("slug", JString "acme"), ("remote", JString "No"), ("remote_confidence", JString "low")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      (merged.remote, merged.remoteConfidence) `shouldBe` ("Yes", Just High)

    forM_ [("missing", []), ("blank", [("remote_confidence", JString " ")]), ("empty", [("remote_confidence", JString "")])] $ \(label, confidenceField) ->
      it ("does not let a finding with a " <> label <> " confidence overwrite a held one") $ do
        -- Arrange
        let existing = sampleCompany {remote = "Yes", remoteEvidence = "careers page", remoteConfidence = Just Low}
            record = inbox ([("slug", JString "acme"), ("remote", JString "No"), ("remote_evidence", JString "blog")] <> confidenceField)
        -- Act
        let merged = mergeOne today "sweep" (Just existing) record
        -- Assert
        (merged.remote, merged.remoteEvidence, merged.remoteConfidence) `shouldBe` ("Yes", "careers page", Just Low)

    it "renames an existing company in place" $ do
      -- Arrange
      let record = inbox [("slug", JString "acme"), ("name", JString "Floodbase")]
      -- Act
      let merged = mergeOne today "sweep" (Just sampleCompany) record
      -- Assert
      merged.name `shouldBe` "Floodbase"

    it "keeps the stored name when the finding's name is blank" $ do
      -- Arrange
      let record = inbox [("slug", JString "acme"), ("name", JString " ")]
      -- Act
      let merged = mergeOne today "sweep" (Just sampleCompany) record
      -- Assert
      merged.name `shouldBe` sampleCompany.name

    it "takes a finding without confidence when none is held" $ do
      -- Arrange
      let existing = sampleCompany {remote = "Yes", remoteConfidence = Nothing}
          record = inbox [("slug", JString "acme"), ("remote", JString "No")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      (merged.remote, merged.remoteConfidence) `shouldBe` ("No", Nothing)

    it "keeps existing link values, incoming keys first, and drops blank links" $ do
      -- Arrange
      let existing = sampleCompany {links = [("linkedin", "old-li"), ("github", "old-gh")]}
          record =
            inbox
              [ ("slug", JString "acme")
              , ("links", JObject [("twitter", JString "https://tw"), ("linkedin", JString "https://new-li"), ("youtube", JString " ")])
              ]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      merged.links `shouldBe` [("twitter", "https://tw"), ("linkedin", "old-li"), ("github", "old-gh")]

    it "stamps a note onto the trimmed body and sets last_checked" $ do
      -- Arrange
      let record = inbox [("slug", JString "acme"), ("note", JString "  careers moved  ")]
      -- Act
      let merged = mergeOne today "sweep" (Just sampleCompany {body = "old text\n"}) record
      -- Assert
      merged.body `shouldBe` "old text\n\n[sweep 2026-10-27] careers moved"
      merged.lastChecked `shouldBe` Just "2026-10-27"

    it "creates a new company from defaults, the slug as name, and flagged locations" $ do
      -- Arrange
      let record =
            inbox
              [ ("slug", JString " newco ")
              , ("careers_url", JString " https://newco.io/jobs ")
              , ("locations", JArray [JString "Berlin"])
              , ("website", JString "")
              ]
      -- Act
      let created = mergeOne today "discovery-sweep" Nothing record
      -- Assert
      (created.name, created.status, created.source, created.website) `shouldBe` ("newco", Unknown, "discovery-sweep", "")
      (created.careersUrls, created.locations, created.listed) `shouldBe` (["https://newco.io/jobs"], ["🇩🇪 Berlin"], False)

    forM_ ["", " ", "Acme Corp", "a/b", "../README", "-acme", "acme-", "a--b"] $ \slug ->
      it ("rejects the slug " <> show slug) $ do
        -- Arrange
        let json = JObject [("slug", JString slug)]
        -- Act
        let decoded = decodeInboxRecord json
        -- Assert
        decoded `shouldSatisfy` isLeft

    it "rejects a web link with no scheme" $ do
      -- Arrange
      let json = JObject [("slug", JString "acme"), ("links", JObject [("youtube", JString "youtube.com/@acme")])]
      -- Act
      let decoded = decodeInboxRecord json
      -- Assert
      decoded `shouldSatisfy` isLeft

    it "accepts a stocks ticker" $ do
      -- Arrange
      let record = inbox [("slug", JString "acme"), ("links", JObject [("stocks", JString "$PL")])]
      -- Act
      let merged = mergeOne today "sweep" (Just sampleCompany {links = []}) record
      -- Assert
      merged.links `shouldBe` [("stocks", "$PL")]

    it "ignores confidence and evidence from a record with no remote value" $ do
      -- Arrange
      let existing = sampleCompany {remote = "", remoteEvidence = "", remoteConfidence = Nothing}
          record = inbox [("slug", JString "acme"), ("remote", JString ""), ("remote_evidence", JString "x"), ("remote_confidence", JString "high")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      (merged.remote, merged.remoteEvidence, merged.remoteConfidence) `shouldBe` ("", "", Nothing)

    it "lets any finding fill a blank remote, whatever confidence is held" $ do
      -- Arrange
      let existing = sampleCompany {remote = "", remoteEvidence = "old", remoteConfidence = Just High}
          record = inbox [("slug", JString "acme"), ("remote", JString "Yes (Europe)"), ("remote_confidence", JString "medium")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      (merged.remote, merged.remoteEvidence, merged.remoteConfidence) `shouldBe` ("Yes (Europe)", "", Just Medium)

    it "moves a stored careers URL that the finding names to the front" $ do
      -- Arrange
      let existing = sampleCompany {careersUrls = ["https://dead.io", "https://live.io"]}
          record = inbox [("slug", JString "acme"), ("careers_url", JString "https://live.io")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      merged.careersUrls `shouldBe` ["https://live.io", "https://dead.io"]

    it "keeps the stored evidence when a finding reconfirms the remote without any" $ do
      -- Arrange
      let existing = sampleCompany {remote = "Yes (US)", remoteEvidence = "posting", remoteConfidence = Just High}
          record = inbox [("slug", JString "acme"), ("remote", JString "Yes (US)"), ("remote_confidence", JString "high")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      merged.remoteEvidence `shouldBe` "posting"

    it "drops the stored evidence when a finding changes the remote without any" $ do
      -- Arrange
      let existing = sampleCompany {remote = "Yes (US)", remoteEvidence = "posting", remoteConfidence = Just Low}
          record = inbox [("slug", JString "acme"), ("remote", JString "Hybrid"), ("remote_confidence", JString "high")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      merged.remoteEvidence `shouldBe` ""

    it "treats a whitespace remote as no finding" $ do
      -- Arrange
      let existing = sampleCompany {remote = "Yes", remoteEvidence = "posting", remoteConfidence = Just High}
          record = inbox [("slug", JString "acme"), ("remote", JString " "), ("remote_confidence", JString "high")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      (merged.remote, merged.remoteEvidence) `shouldBe` ("Yes", "posting")

    it "replaces only the first careers URL with a new one" $ do
      -- Arrange
      let existing = sampleCompany {careersUrls = ["https://a.io", "https://b.io"]}
          record = inbox [("slug", JString "acme"), ("careers_url", JString "https://c.io")]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      merged.careersUrls `shouldBe` ["https://c.io", "https://b.io"]

    forM_ [("website", "acme.io"), ("careers_url", "jobs.acme.io"), ("careers_url", "httpbin.org/jobs")] $ \(key, value) ->
      it ("rejects " <> show key <> " " <> show value) $ do
        -- Arrange
        let json = JObject [("slug", JString "acme"), (key, JString value)]
        -- Act
        let decoded = decodeInboxRecord json
        -- Assert
        decoded `shouldSatisfy` isLeft

    it "rejects a link that only starts with the letters http" $ do
      -- Arrange
      let json = JObject [("slug", JString "acme"), ("links", JObject [("github", JString "httpbin.org/acme")])]
      -- Act
      let decoded = decodeInboxRecord json
      -- Assert
      decoded `shouldSatisfy` isLeft

    it "rejects an unknown status word" $ do
      -- Arrange
      let json = JObject [("slug", JString "acme"), ("status", JString "dead")]
      -- Act
      let decoded = decodeInboxRecord json
      -- Assert
      decoded `shouldBe` Left "field 'status': unknown value \"dead\""

  describe "Merge.run" $ do
    it "saves nothing when a later inbox file has a bad record, and names it" $ inScratchDir "merge" $ do
      -- Arrange
      createDirectoryIfMissing True "companies/_inbox"
      writeUtf8 "companies/_inbox/a.json" "[{\"slug\":\"acme\",\"note\":\"seen\"}]"
      writeUtf8 "companies/_inbox/b.json" "[{\"slug\":\"beta\"},{\"slug\":\"gamma\",\"status\":\"dead\"}]"
      -- Act
      failure <- failureMessage (Merge.run "sweep")
      -- Assert
      failure `shouldSatisfy` maybe False ("companies/_inbox/b.json: record 1: field 'status'" `isInfixOf`)
      saved <- traverse doesFileExist ["companies/acme.md", "companies/beta.md"]
      saved `shouldBe` [False, False]

    it "leaves verdict files alone and deletes the files it merged" $ inScratchDir "merge-inbox" $ do
      -- Arrange
      createDirectoryIfMissing True "companies/_inbox"
      writeUtf8 "companies/_inbox/class_1.json" "[{\"slug\":\"typo\",\"type\":\"software\"}]"
      writeUtf8 "companies/_inbox/refresh_1.json" "[{\"slug\":\"acme\",\"note\":\"seen\"}]"
      -- Act
      Merge.run "sweep"
      -- Assert
      present <- traverse doesFileExist ["companies/acme.md", "companies/typo.md", "companies/_inbox/class_1.json", "companies/_inbox/refresh_1.json"]
      present `shouldBe` [True, False, True, False]

    it "keeps the file when a record has no slug" $ inScratchDir "merge-no-slug" $ do
      -- Arrange
      createDirectoryIfMissing True "companies/_inbox"
      writeUtf8 "companies/_inbox/disc_1.json" "[{\"name\":\"Acme\"}]"
      -- Act
      failure <- failureMessage (Merge.run "sweep")
      -- Assert
      failure `shouldSatisfy` maybe False ("field 'slug'" `isInfixOf`)
      fileKept <- doesFileExist "companies/_inbox/disc_1.json"
      fileKept `shouldBe` True

  describe "Dedup.run" $ do
    it "deletes no dropped file when a later one in the group fails to read" $ inScratchDir "dedup" $ do
      -- Arrange
      createDirectoryIfMissing True "companies"
      writeUtf8 "companies/keep.md" sampleFile
      writeUtf8 "companies/alpha.md" sampleFile
      writeUtf8 "companies/broken.md" "not a company file"
      writeUtf8 "known_duplicates.json" "[{\"slugs\":[\"keep\",\"alpha\",\"broken\"],\"keep\":\"keep\"}]"
      -- Act
      failure <- failureMessage Dedup.run
      -- Assert
      failure `shouldSatisfy` maybe False ("companies/broken.md" `isInfixOf`)
      alphaKept <- doesFileExist "companies/alpha.md"
      alphaKept `shouldBe` True
      keeperText <- readUtf8 "companies/keep.md"
      keeperText `shouldBe` sampleFile

    it "saves the keeper with the absorbed duplicates, then deletes them" $ inScratchDir "dedup-ok" $ do
      -- Arrange
      createDirectoryIfMissing True "companies"
      writeUtf8 "companies/keep.md" sampleFile
      writeUtf8 "companies/alpha.md" (T.replace "acme.io/jobs" "alpha.io/jobs" sampleFile)
      writeUtf8 "known_duplicates.json" "[{\"slugs\":[\"keep\",\"alpha\",\"alpha\"],\"keep\":\"keep\",\"reason\":\"same\"}]"
      -- Act
      Dedup.run
      -- Assert
      alphaKept <- doesFileExist "companies/alpha.md"
      alphaKept `shouldBe` False
      keeper <- either (error . T.unpack) id . parseCompany <$> readUtf8 "companies/keep.md"
      keeper.careersUrls `shouldBe` ["https://acme.io/jobs", "https://alpha.io/jobs"]

  describe "absorbDuplicates" $ do
    let group = Dedup.DuplicateGroup ["keep", "drop"] "keep" "same"
        finding = sampleCompany {remote = "Yes (US)", remoteEvidence = "posting", remoteConfidence = Just High, description = "From the dropped file.", body = "research notes"}

    it "fills the keeper's blank remote and description from the dropped company" $ do
      -- Arrange
      let keeper = sampleCompany {remote = "", remoteEvidence = "", remoteConfidence = Just High, description = ""}
      -- Act
      let merged = Dedup.absorbDuplicates group keeper [("drop", finding)]
      -- Assert
      (merged.remote, merged.remoteEvidence, merged.remoteConfidence, merged.description)
        `shouldBe` ("Yes (US)", "posting", Just High, "From the dropped file.")

    it "keeps the keeper's filled remote and description" $ do
      -- Arrange
      let keeper = sampleCompany {remote = "Hybrid", remoteEvidence = "site", remoteConfidence = Just Low}
      -- Act
      let merged = Dedup.absorbDuplicates group keeper [("drop", finding)]
      -- Assert
      (merged.remote, merged.remoteEvidence, merged.remoteConfidence, merged.description)
        `shouldBe` ("Hybrid", "site", Just Low, keeper.description)

    it "joins the bodies and then notes the merge" $ do
      -- Arrange
      let keeper = sampleCompany {body = "kept notes\n"}
      -- Act
      let merged = Dedup.absorbDuplicates group keeper [("drop", finding)]
      -- Assert
      merged.body `shouldBe` "kept notes\n\nresearch notes\n\n[dedup] merged duplicate(s) drop — same"

  describe "classifyOne" $ do
    let verdicts = Map.fromList [("trimble", Verdict Software "agent says" Nothing), ("acme", Verdict Consultancy "services" Nothing)]

    it "applies a verdict to every slug, with no forced override" $ do
      -- Arrange
      let company = sampleCompany {companyType = Just Conglomerate}
      -- Act
      let classified = classifyOne verdicts "trimble" company
      -- Assert
      (classified.companyType, classified.typeReason) `shouldBe` (Just Software, Just "agent says [agent]")

    it "keeps the stored type when there is no verdict" $ do
      -- Arrange
      let company = sampleCompany {companyType = Just Conglomerate, typeReason = Just "many divisions"}
      -- Act
      let classified = classifyOne Map.empty "trimble" company
      -- Assert
      (classified.companyType, classified.typeReason) `shouldBe` (Just Conglomerate, Just "many divisions")

    it "lets an agent verdict beat the existing type" $ do
      -- Arrange
      let company = sampleCompany {companyType = Just CommercialEo}
      -- Act
      let classified = classifyOne verdicts "acme" company
      -- Assert
      (classified.companyType, classified.typeReason) `shouldBe` (Just Consultancy, Just "services [agent]")

    it "does not give a type to a company without a verdict, or list it" $ do
      -- Arrange
      let company = sampleCompany {companyType = Nothing, typeReason = Nothing}
      -- Act
      let classified = classifyOne Map.empty "other" company
      -- Assert
      (classified.companyType, classified.typeReason, classified.listed) `shouldBe` (Nothing, Nothing, False)

    forM_ (filter (/= NotEo) [minBound .. maxBound]) $ \companyType ->
      it ("lists an active " <> show companyType <> " company with an http careers URL") $ do
        -- Arrange
        let company = sampleCompany {companyType = Just companyType}
        -- Act
        let classified = classifyOne Map.empty "other" company
        -- Assert
        classified.listed `shouldBe` True

    it "does not list a not-eo company" $ do
      -- Arrange
      let company = sampleCompany {companyType = Just NotEo}
      -- Act
      let classified = classifyOne Map.empty "other" company
      -- Assert
      classified.listed `shouldBe` False

    it "does not list a company with an unlisted_reason, and keeps it without a verdict" $ do
      -- Arrange
      let company = sampleCompany {unlistedReason = Just "no EO roles"}
      -- Act
      let classified = classifyOne Map.empty "other" company
      -- Assert
      (classified.listed, classified.unlistedReason) `shouldBe` (False, Just "no EO roles")

    it "sets unlisted_reason from a verdict" $ do
      -- Arrange
      let setting = Map.fromList [("acme", Verdict Conglomerate "big" (Just "no EO roles"))]
      -- Act
      let classified = classifyOne setting "acme" sampleCompany
      -- Assert
      (classified.listed, classified.unlistedReason) `shouldBe` (False, Just "no EO roles")

    it "clears a stored unlisted_reason when a verdict has none" $ do
      -- Arrange
      let company = sampleCompany {unlistedReason = Just "no EO roles"}
      -- Act
      let classified = classifyOne verdicts "acme" company
      -- Assert
      (classified.listed, classified.unlistedReason) `shouldBe` (True, Nothing)

    it "does not list a company without an http careers URL" $ do
      -- Arrange
      let company = sampleCompany {careersUrls = ["mailto:jobs@acme.io"]}
      -- Act
      let classified = classifyOne Map.empty "other" company
      -- Assert
      classified.listed `shouldBe` False

  describe "Classify.run" $ do
    it "saves nothing when a verdict names an unknown slug" $ inScratchDir "classify" $ do
      -- Arrange
      createDirectoryIfMissing True "companies/_inbox"
      writeUtf8 "companies/acme.md" sampleFile
      writeUtf8 "companies/_inbox/class_1.json" "[{\"slug\":\"typo\",\"type\":\"software\"}]"
      -- Act
      failure <- failureMessage Classify.run
      -- Assert
      failure `shouldSatisfy` maybe False ("unknown slug: typo" `isInfixOf`)
      acmeText <- readUtf8 "companies/acme.md"
      acmeText `shouldBe` sampleFile

  describe "decodeVerdicts" $ do
    let verdictJson unlistedField =
          JArray [JObject ([("slug", JString "acme"), ("type", JString "conglomerate"), ("reason", JString "big")] <> unlistedField)]

    it "reads unlisted_reason" $ do
      -- Arrange
      let json = verdictJson [("unlisted_reason", JString "no EO roles")]
      -- Act
      let decoded = decodeVerdicts json
      -- Assert
      decoded `shouldBe` Right [("acme", Verdict Conglomerate "big" (Just "no EO roles"))]

    forM_ [("invalid", [("slug", JString "acme"), ("type", JString "softwre")]), ("missing", [("slug", JString "acme")])] $ \(label, pairs) ->
      it ("fails on a verdict whose type is " <> label) $ do
        -- Arrange
        let json = JArray [JObject pairs]
        -- Act
        let decoded = decodeVerdicts json
        -- Assert
        decoded `shouldSatisfy` isLeft

    forM_ [("missing", []), ("blank", [("unlisted_reason", JString " ")])] $ \(label, unlistedField) ->
      it ("treats a " <> label <> " unlisted_reason as absent") $ do
        -- Arrange
        let json = verdictJson unlistedField
        -- Act
        let decoded = decodeVerdicts json
        -- Assert
        decoded `shouldBe` Right [("acme", Verdict Conglomerate "big" Nothing)]

  describe "fixupOne" $ do
    it "normalizes remote and flags unflagged locations" $ do
      -- Arrange
      let company = sampleCompany {remote = "US-based", locations = ["Seattle", "🇬🇧 London"]}
      -- Act
      let result = fixupOne company
      -- Assert
      (result.fixed.remote, result.fixed.locations) `shouldBe` ("Yes (US)", ["🇺🇸 Seattle", "🇬🇧 London"])
      (result.remoteChanged, result.locationsFlagged) `shouldBe` (True, 1)

    it "leaves a clean company unchanged" $ do
      -- Arrange
      let company = sampleCompany
      -- Act
      let result = fixupOne company
      -- Assert
      (result.fixed, result.remoteChanged, result.locationsFlagged) `shouldBe` (company, False, 0)

  describe "classInputLine" $ do
    it "shows a stored unlisted_reason to the classifying agent" $ do
      -- Arrange
      let company = sampleCompany {unlistedReason = Just "general portal"}
      -- Act
      let line = classInputLine "acme" company
      -- Assert
      line `shouldSatisfy` T.isInfixOf "\"unlisted_reason\":\"general portal\""

    it "leaves unlisted_reason out when none is stored" $ do
      -- Arrange
      let company = sampleCompany {unlistedReason = Nothing}
      -- Act
      let line = classInputLine "acme" company
      -- Assert
      line `shouldNotSatisfy` T.isInfixOf "unlisted_reason"

  describe "introLinks" $ do
    it "returns each markdown and html link once, without its closing punctuation" $ do
      -- Arrange
      let markdown = "[a](https://a.io/x?y=1) and <a href=\"http://b.io\">b</a>\n[again](https://a.io/x?y=1) http is a word"
      -- Act
      let links = introLinks markdown
      -- Assert
      links `shouldBe` ["https://a.io/x?y=1", "http://b.io"]

  describe "regDomain" $ do
    let cases =
          [ ("https://www.example.com/careers", "example.com")
          , ("https://jobs.bbc.co.uk/x", "bbc.co.uk")
          , ("example.com", "example.com")
          , ("httpbin.org/x", "httpbin.org")
          , ("https://a.b.example.org", "example.org")
          , ("https://localhost:8080", "localhost")
          , ("", "")
          ]
    forM_ cases $ \(url, expected) ->
      it ("reduces " <> show url) $ do
        -- Arrange (the case table above)
        -- Act
        let domain = regDomain url
        -- Assert
        domain `shouldBe` expected

  describe "isAliveStatus" $ do
    let cases =
          [(200, True), (301, True), (403, True), (404, False), (410, False), (429, True), (500, False), (999, True)]
    forM_ cases $ \(status, expected) ->
      it ("judges " <> show status) $ do
        -- Arrange (the case table above)
        -- Act
        let verdict = isAliveStatus status
        -- Assert
        verdict `shouldBe` expected

-- | Run @action@ in a fresh empty directory, so commands that use the relative
-- @companies/@ paths never touch the real DB.
inScratchDir :: String -> IO a -> IO a
inScratchDir label action = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> ("eojobs-spec-" <> label)
  removePathForcibly dir
  createDirectoryIfMissing True dir
  withCurrentDirectory dir action

-- | The IO error @action@ fails with, or 'Nothing' when it succeeds.
failureMessage :: IO a -> IO (Maybe String)
failureMessage action = either (Just . show) (const Nothing) <$> try @IOException action

roundTripMismatch :: FilePath -> IO [FilePath]
roundTripMismatch path = do
  original <- readUtf8 path
  pure $ case parseCompany original of
    Right company | renderCompany company == original -> []
    _ -> [path]

inbox :: [(Text, Json)] -> InboxRecord
inbox pairs = either (error . T.unpack) id (decodeInboxRecord (JObject pairs))

sampleFile :: Text
sampleFile =
  T.unlines
    [ "---"
    , "name: \"Acme EO\""
    , "status: \"active\""
    , "website: \"https://acme.io\""
    , "careers_urls: [\"https://acme.io/jobs\"]"
    , "locations: [\"🇬🇧 London\"]"
    , "remote: \"Hybrid\""
    , "remote_evidence: \"\""
    , "description: \"Satellite analytics.\""
    , "satellites: \"\""
    , "category: \"\""
    , "listed: true"
    , "links: {\"linkedin\":\"https://linkedin.com/acme\"}"
    , "source: \"seed\""
    , "type: \"commercial-eo\""
    , "type_reason: \"makes EO products\""
    , "---"
    ]

sampleCompany :: Company
sampleCompany = either (error . T.unpack) id (parseCompany sampleFile)
