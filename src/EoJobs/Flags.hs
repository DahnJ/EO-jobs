-- | Prepend a flag emoji (or globe) to a location string. Flags are derived from
-- ISO-3166 alpha-2 codes via regional-indicator code points, so adding a country
-- is one table entry.
module EoJobs.Flags
  ( addFlag
  , flagAll
  , hasFlag
  ) where

import Data.Char (chr, ord, toUpper)
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import EoJobs.StringRules (isBlank, trim)

isoToFlag :: Text -> Text
isoToFlag = T.map (\c -> chr (0x1F1E6 + ord (toUpper c) - ord 'A'))

-- The scans below walk these tables in the order written. The Clojure original
-- walked its hash maps in hash order, which differs; that matters only for a
-- location naming two keywords with different flags (e.g. "Remote (Europe)").
country :: [(Text, Text)]
country =
  [ ("united states", "US"), ("usa", "US"), ("u.s.", "US"), ("u.s.a", "US"), ("us", "US")
  , ("united kingdom", "GB"), ("uk", "GB"), ("u.k.", "GB"), ("england", "GB")
  , ("scotland", "GB"), ("wales", "GB"), ("northern ireland", "GB"), ("britain", "GB")
  , ("france", "FR"), ("germany", "DE"), ("netherlands", "NL"), ("the netherlands", "NL")
  , ("spain", "ES"), ("italy", "IT"), ("portugal", "PT"), ("belgium", "BE")
  , ("luxembourg", "LU"), ("switzerland", "CH"), ("austria", "AT"), ("ireland", "IE")
  , ("sweden", "SE"), ("norway", "NO"), ("denmark", "DK"), ("finland", "FI")
  , ("iceland", "IS"), ("poland", "PL"), ("czech republic", "CZ"), ("czechia", "CZ")
  , ("slovakia", "SK"), ("slovenia", "SI"), ("hungary", "HU"), ("romania", "RO")
  , ("bulgaria", "BG"), ("greece", "GR"), ("croatia", "HR"), ("serbia", "RS")
  , ("ukraine", "UA"), ("belarus", "BY"), ("estonia", "EE"), ("latvia", "LV")
  , ("lithuania", "LT"), ("russia", "RU"), ("turkey", "TR"), ("türkiye", "TR")
  , ("cyprus", "CY"), ("malta", "MT"), ("uzbekistan", "UZ"), ("kazakhstan", "KZ")
  , ("canada", "CA"), ("mexico", "MX"), ("brazil", "BR"), ("argentina", "AR")
  , ("chile", "CL"), ("colombia", "CO"), ("peru", "PE"), ("uruguay", "UY")
  , ("ecuador", "EC"), ("bolivia", "BO"), ("china", "CN"), ("japan", "JP")
  , ("south korea", "KR"), ("korea", "KR"), ("india", "IN"), ("singapore", "SG")
  , ("taiwan", "TW"), ("hong kong", "HK"), ("indonesia", "ID"), ("malaysia", "MY")
  , ("thailand", "TH"), ("vietnam", "VN"), ("philippines", "PH"), ("pakistan", "PK")
  , ("bangladesh", "BD"), ("sri lanka", "LK"), ("australia", "AU")
  , ("new zealand", "NZ"), ("israel", "IL"), ("uae", "AE")
  , ("united arab emirates", "AE"), ("saudi arabia", "SA"), ("qatar", "QA")
  , ("kuwait", "KW"), ("bahrain", "BH"), ("oman", "OM"), ("jordan", "JO")
  , ("lebanon", "LB"), ("egypt", "EG"), ("south africa", "ZA"), ("kenya", "KE")
  , ("nigeria", "NG"), ("ghana", "GH"), ("tanzania", "TZ"), ("uganda", "UG")
  , ("rwanda", "RW"), ("ethiopia", "ET"), ("morocco", "MA"), ("tunisia", "TN")
  , ("senegal", "SN"), ("azerbaijan", "AZ"), ("georgia", "GE"), ("armenia", "AM")
  , ("iraq", "IQ"), ("iran", "IR")
  ]

city :: [(Text, Text)]
city =
  -- UK
  [ ("london", "GB"), ("edinburgh", "GB"), ("glasgow", "GB"), ("bristol", "GB")
  , ("oxford", "GB"), ("cambridge", "GB"), ("reading", "GB"), ("guildford", "GB")
  , ("plymouth", "GB"), ("didcot", "GB"), ("harwell", "GB"), ("skipton", "GB")
  , ("leicester", "GB"), ("belfast", "GB"), ("musselburgh", "GB"), ("sywell", "GB")
  , ("northamptonshire", "GB")
  -- US
  , ("seattle", "US"), ("boston", "US"), ("berkeley", "US"), ("denver", "US")
  , ("houston", "US"), ("midland", "US"), ("austin", "US"), ("madison", "US")
  , ("santa fe", "US"), ("washington", "US"), ("san mateo", "US"), ("bozeman", "US")
  , ("lafayette", "US"), ("north potomac", "US"), ("san francisco", "US")
  , ("new york", "US"), ("montana", "US"), ("california", "US"), ("colorado", "US")
  , ("texas", "US"), ("wi", "US"), ("tx", "US"), ("ca", "US"), ("wa", "US"), ("co", "US")
  , ("ny", "US"), ("ma", "US")
  -- other
  , ("sydney", "AU"), ("melbourne", "AU"), ("seoul", "KR"), ("tokyo", "JP")
  , ("singapore", "SG"), ("amsterdam", "NL"), ("zwolle", "NL"), ("hamburg", "DE")
  , ("munich", "DE"), ("berlin", "DE"), ("paris", "FR"), ("toulouse", "FR")
  , ("hyderabad", "IN"), ("bangalore", "IN"), ("bengaluru", "IN"), ("changchun", "CN")
  , ("vancouver", "CA"), ("halifax", "CA"), ("calgary", "CA"), ("toronto", "CA")
  , ("zurich", "CH"), ("zürich", "CH"), ("vienna", "AT"), ("graz", "AT")
  , ("warsaw", "PL"), ("wrocław", "PL"), ("wroclaw", "PL"), ("kraków", "PL")
  , ("krakow", "PL"), ("gliwice", "PL"), ("piaseczno", "PL"), ("brussels", "BE")
  , ("liege", "BE"), ("liège", "BE"), ("mont-saint-guibert", "BE"), ("athens", "GR")
  , ("lisbon", "PT"), ("porto", "PT"), ("brno", "CZ"), ("prague", "CZ")
  , ("sofia", "BG"), ("ljubljana", "SI"), ("bratislava", "SK"), ("tashkent", "UZ")
  , ("minsk", "BY"), ("lagos", "NG"), ("abuja", "NG"), ("johannesburg", "ZA")
  , ("nairobi", "KE"), ("buenos aires", "AR"), ("ayacucho", "PE")
  , ("esch-sur-alzette", "LU"), ("abu dhabi", "AE"), ("dubai", "AE")
  ]

region :: [(Text, Text)]
region =
  -- continents before global words: "Remote (Europe)" is 🌍, not 🌐
  [ ("europe", "🌍"), ("asia pacific", "🌏"), ("asia", "🌏"), ("africa", "🌍")
  , ("remote", "🌐"), ("global", "🌐"), ("worldwide", "🌐"), ("anywhere", "🌐")
  , ("world", "🌐"), ("many locations", "🌐"), ("many countries", "🌐")
  , ("multiple continents", "🌐")
  ]

countryByName, cityByName :: Map.Map Text Text
countryByName = Map.fromList country
cityByName = Map.fromList city

-- | True if the location already starts with a flag or globe.
hasFlag :: Text -> Bool
hasFlag loc = case T.uncons loc of
  Just (c, _) -> isRegionalIndicator c || isGlobe c
  Nothing -> False
  where
    isRegionalIndicator c = c >= '\x1F1E6' && c <= '\x1F1FF'
    isGlobe c = c >= '\x1F30D' && c <= '\x1F310' -- 🌍 🌎 🌏 🌐

-- | Best-guess flag for a location string.
detect :: Text -> Maybe Text
detect loc =
  firstJust
    [ -- last token first: the country is usually rightmost and most reliable
      listToMaybe (mapMaybe tokenFlag (reverse tokens))
    , snd <$> find ((`T.isInfixOf` lowered) . fst) region
    , -- fallback: any country/city name longer than 3 letters anywhere
      nameAnywhere country
    , nameAnywhere city
    ]
  where
    lowered = T.toLower (trim loc)
    tokens = filter (not . isBlank) (map trim (T.splitOn "," (T.replace ";" "," lowered)))
    tokenFlag tok = isoToFlag <$> firstJust [Map.lookup tok countryByName, Map.lookup tok cityByName]
    nameAnywhere table =
      isoToFlag . snd <$> find (\(n, _) -> T.length n > 3 && n `T.isInfixOf` lowered) table
    firstJust = listToMaybe . concatMap (maybe [] pure)

-- | The location with a leading flag or globe; unchanged if it has one already
-- or none fits.
addFlag :: Text -> Text
addFlag loc
  | isBlank loc || hasFlag loc = loc
  | otherwise = maybe loc (\flag -> flag <> " " <> loc) (detect loc)

flagAll :: [Text] -> [Text]
flagAll = map addFlag
