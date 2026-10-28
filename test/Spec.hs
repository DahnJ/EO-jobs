module Main (main) where

import Control.Monad (forM_)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (fromGregorian)
import EoJobs.Classify (Verdict (..), classifyOne)
import EoJobs.Company
import EoJobs.Db (listMatching, parseCompany, readUtf8, renderCompany, hasExtension)
import EoJobs.Fixup (FixupResult (..), fixupOne)
import EoJobs.Flags (addFlag)
import EoJobs.Json
import EoJobs.Merge (InboxRecord (..), decodeInboxRecord, mergeOne)
import EoJobs.Net (isAliveStatus, regDomain)
import EoJobs.Readme (renderReadme)
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

    it "fails with the field name when a required field is missing" $ do
      -- Arrange
      let withoutStatus = T.unlines (filter (not . ("status:" `T.isPrefixOf`)) (T.lines sampleFile))
      -- Act
      let result = parseCompany withoutStatus
      -- Assert
      result `shouldBe` Left "missing field 'status'"

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

    it "keeps existing link values, incoming keys first, and drops blank links" $ do
      -- Arrange
      let existing = sampleCompany {links = [("linkedin", "old-li"), ("github", "old-gh")]}
          record =
            inbox
              [ ("slug", JString "acme")
              , ("links", JObject [("twitter", JString "tw"), ("linkedin", JString "new-li"), ("youtube", JString " ")])
              ]
      -- Act
      let merged = mergeOne today "sweep" (Just existing) record
      -- Assert
      merged.links `shouldBe` [("twitter", "tw"), ("linkedin", "old-li"), ("github", "old-gh")]

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

    it "rejects an unknown status word" $ do
      -- Arrange
      let json = JObject [("slug", JString "acme"), ("status", JString "dead")]
      -- Act
      let decoded = decodeInboxRecord json
      -- Assert
      decoded `shouldBe` Left "field 'status': unknown value \"dead\""

  describe "classifyOne" $ do
    let verdicts = Map.fromList [("trimble", Verdict Software "agent says"), ("acme", Verdict Consultancy "services")]

    it "lets the conglomerate override beat an agent verdict" $ do
      -- Arrange
      let company = sampleCompany
      -- Act
      let classified = classifyOne verdicts "trimble" company
      -- Assert
      (classified.companyType, classified.typeReason, classified.listed)
        `shouldBe` (Just Conglomerate, Just "known large multi-division company", False)

    it "lets an agent verdict beat the existing type" $ do
      -- Arrange
      let company = sampleCompany {companyType = Just CommercialEo}
      -- Act
      let classified = classifyOne verdicts "acme" company
      -- Assert
      (classified.companyType, classified.typeReason) `shouldBe` (Just Consultancy, Just "services [agent]")

    it "lists an active commercial-eo company with an http careers URL" $ do
      -- Arrange
      let company = sampleCompany {companyType = Nothing, typeReason = Nothing}
      -- Act
      let classified = classifyOne Map.empty "other" company
      -- Assert
      (classified.companyType, classified.typeReason, classified.listed)
        `shouldBe` (Just CommercialEo, Just "unclassified", True)

    it "does not list a company without an http careers URL" $ do
      -- Arrange
      let company = sampleCompany {careersUrls = ["mailto:jobs@acme.io"]}
      -- Act
      let classified = classifyOne Map.empty "other" company
      -- Assert
      classified.listed `shouldBe` False

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

  describe "regDomain" $ do
    let cases =
          [ ("https://www.example.com/careers", "example.com")
          , ("https://jobs.bbc.co.uk/x", "bbc.co.uk")
          , ("example.com", "example.com")
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
