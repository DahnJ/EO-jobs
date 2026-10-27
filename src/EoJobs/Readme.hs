-- | Generate README.md from the DB. Only listed companies appear. Each table
-- cell is minimal-width so refresh diffs stay row-local; GitHub renders it the
-- same as a padded table.
module EoJobs.Readme
  ( renderReadme
  , run
  ) where

import Data.List (sortOn)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import EoJobs.Company
import EoJobs.Db
import EoJobs.StringRules (utf16Order)

businessIcons, socialIcons :: [(Text, Text)]
businessIcons =
  [ ("crunchbase", "https://i.imgur.com/H3e6fly.png")
  , ("spac", "https://i.imgur.com/BjJ1vkt.png")
  ]
socialIcons =
  [ ("twitter", "https://i.imgur.com/d4HTDdM.png")
  , ("youtube", "https://i.imgur.com/P1O5Rjh.png")
  , ("github", "https://i.imgur.com/5rpIT2Z.png")
  , ("linkedin", "https://i.imgur.com/SSBwtJu.png")
  ]

columns :: [Text]
columns = ["Name", "Description", "Jobs", "Locations", "Remote", "Social", "Business"]

icons :: [(Text, Text)] -> [(Text, Text)] -> Text
icons links iconSources =
  T.concat
    [ "<a href=\"" <> url <> "\"><img src=" <> src <> " height=25></a>"
    | (key, src) <- iconSources
    , Just url <- [lookup key links]
    ]

row :: Company -> [Text]
row c =
  [ "<a href=\"" <> c.website <> "\">" <> c.name <> "</a>"
  , c.description
  , T.concat ["<a href=\"" <> url <> "\">[" <> T.pack (show i) <> "]</a>" | (i, url) <- zip [1 :: Int ..] c.careersUrls]
  , T.intercalate "<br />" c.locations
  , if c.remote `elem` ["", "No", "No jobs"] then "" else c.remote
  , icons c.links socialIcons
  , icons c.links businessIcons
  ]

-- | README text: the intro, then a table of listed companies sorted by name.
renderReadme :: Text -> [Company] -> Text
renderReadme intro companies = intro <> T.intercalate "\n" (header <> map tableRow rows) <> "\n"
  where
    rows = sortOn (utf16Order . T.toLower . (.name)) (filter (.listed) companies)
    header =
      [ "| " <> T.intercalate " | " columns <> " |"
      , "|" <> T.intercalate "|" (map (const ":---") columns) <> "|"
      ]
    tableRow c = "| " <> T.intercalate " | " (row c) <> " |"

-- | Rewrite README.md from @intro.md@ and the DB.
run :: IO ()
run = do
  intro <- readUtf8 "intro.md"
  companies <- map snd <$> loadAll
  writeUtf8 "README.md" (renderReadme intro companies)
  TIO.putStrLn ("Wrote README.md ( " <> T.pack (show (length (filter (.listed) companies))) <> " companies)")
