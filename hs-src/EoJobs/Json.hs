-- | A JSON value that keeps object key order, with a parser and an encoder that
-- matches cheshire/Jackson @generate-string@ byte-for-byte. Not aeson: aeson
-- sorts object keys, which would rewrite the @links@ order of hundreds of files.
module EoJobs.Json
  ( Json (..)
  , JsonNumber (..)
  , parseJson
  , encodeJson
    -- * Decoding helpers
  , Decoder
  , text
  , bool
  , list
  , object
  , vocabulary
  , field
  , optionalField
  ) where

import Data.Bifunctor (first)
import Data.Char (chr, digitToInt, isDigit, isHexDigit, ord)
import Data.Containers.ListUtils (nubOrd)
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Builder as B
import Data.Void (Void)
import Numeric (showHex)
import Text.Megaparsec
import Text.Megaparsec.Char (char, string)

data JsonNumber
  = IntegerNumber Integer
  | DecimalNumber Double
  deriving (Eq, Show)

data Json
  = JNull
  | JBool Bool
  | JNumber JsonNumber
  | JString Text
  | JArray [Json]
  | JObject [(Text, Json)]
  deriving (Eq, Show)

type Parser = Parsec Void Text

-- | Parse one JSON document (surrounding whitespace allowed). A repeated object
-- key keeps its first position and its last value, as cheshire does.
parseJson :: Text -> Either Text Json
parseJson input = first (T.pack . errorBundlePretty) (parse (spaces *> value <* eof) "json" input)

spaces :: Parser ()
spaces = () <$ takeWhileP Nothing (`elem` [' ', '\t', '\n', '\r'])

lexeme :: Parser a -> Parser a
lexeme p = p <* spaces

value :: Parser Json
value =
  lexeme $
    choice
      [ JNull <$ string "null"
      , JBool True <$ string "true"
      , JBool False <$ string "false"
      , JString <$> stringLiteral
      , JNumber <$> number
      , JArray <$> between (lexeme (char '[')) (char ']') (value `sepBy` lexeme (char ','))
      , JObject . dedupeKeys <$> between (lexeme (char '{')) (char '}') (member `sepBy` lexeme (char ','))
      ]
  where
    member = (,) <$> lexeme stringLiteral <* lexeme (char ':') <*> value

dedupeKeys :: [(Text, Json)] -> [(Text, Json)]
dedupeKeys pairs = mapMaybe (\key -> (key,) <$> Map.lookup key lastValue) (nubOrd (map fst pairs))
  where
    lastValue = Map.fromList pairs

number :: Parser JsonNumber
number = do
  sign <- option "" ("-" <$ char '-')
  intPart <- string "0" <|> takeWhile1P (Just "digit") isDigit
  fraction <- optional (T.cons '.' <$> (char '.' *> takeWhile1P (Just "digit") isDigit))
  exponent' <- optional $ do
    e <- char 'e' <|> char 'E'
    expSign <- option "" (T.singleton <$> (char '+' <|> char '-'))
    digits <- takeWhile1P (Just "digit") isDigit
    pure (T.singleton e <> expSign <> digits)
  let literal = sign <> intPart
  pure $ case (fraction, exponent') of
    (Nothing, Nothing) -> IntegerNumber (read (T.unpack literal))
    _ -> DecimalNumber (read (T.unpack (literal <> fromMaybe ".0" fraction <> maybe "" (T.replace "e+" "e" . T.replace "E" "e") exponent')))

stringLiteral :: Parser Text
stringLiteral = char '"' *> (T.pack . combineSurrogates <$> manyTill stringChar (char '"'))
  where
    stringChar = (char '\\' *> escape) <|> anySingle
    escape =
      choice
        [ '"' <$ char '"'
        , '\\' <$ char '\\'
        , '/' <$ char '/'
        , '\b' <$ char 'b'
        , '\f' <$ char 'f'
        , '\n' <$ char 'n'
        , '\r' <$ char 'r'
        , '\t' <$ char 't'
        , char 'u' *> (chr . foldl' (\acc d -> acc * 16 + digitToInt d) 0 <$> count 4 (satisfy isHexDigit))
        ]

-- | @\\uD83C\\uDF0D@ escapes arrive as two halves; join them into one code point.
-- A lone half cannot live in 'Text', so it becomes U+FFFD.
combineSurrogates :: String -> String
combineSurrogates = \case
  high : low : rest
    | isHigh high && isLow low ->
        chr (0x10000 + (ord high - 0xD800) * 0x400 + (ord low - 0xDC00)) : combineSurrogates rest
  c : rest
    | isHigh c || isLow c -> '\xFFFD' : combineSurrogates rest
    | otherwise -> c : combineSurrogates rest
  [] -> []
  where
    isHigh c = c >= '\xD800' && c <= '\xDBFF'
    isLow c = c >= '\xDC00' && c <= '\xDFFF'

-- | Compact JSON exactly as Jackson writes it: no spaces, only @\"@, @\\@ and
-- control characters escaped; @/@ and non-ASCII are written raw.
encodeJson :: Json -> Text
encodeJson = TL.toStrict . B.toLazyText . build
  where
    build = \case
      JNull -> "null"
      JBool True -> "true"
      JBool False -> "false"
      JNumber (IntegerNumber n) -> B.fromString (show n)
      -- Haskell's Double rendering differs from Java's for very large/small
      -- magnitudes; no data on disk carries a decimal number.
      JNumber (DecimalNumber d) -> B.fromString (show d)
      JString s -> quoted s
      JArray items -> "[" <> commaSeparated (map build items) <> "]"
      JObject pairs -> "{" <> commaSeparated [quoted k <> ":" <> build v | (k, v) <- pairs] <> "}"
    commaSeparated = mconcat . intersperseB ","
    intersperseB _ [] = []
    intersperseB sep (x : xs) = x : concatMap (\y -> [sep, y]) xs
    quoted s = "\"" <> T.foldr (\c acc -> escapeChar c <> acc) mempty s <> "\""
    escapeChar = \case
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\r' -> "\\r"
      '\t' -> "\\t"
      '\b' -> "\\b"
      '\f' -> "\\f"
      c
        | c < ' ' -> B.fromString ("\\u00" <> hex2 (ord c))
        | otherwise -> B.singleton c
    hex2 n = map toUpperHex (pad (showHex n ""))
    pad s = replicate (2 - length s) '0' <> s
    toUpperHex c = if c >= 'a' && c <= 'f' then chr (ord c - 32) else c

-- | Turns a JSON value into a typed one, or says what was wrong with it.
type Decoder a = Json -> Either Text a

text :: Decoder Text
text = \case
  JString s -> Right s
  other -> Left ("expected a string, got " <> describe other)

bool :: Decoder Bool
bool = \case
  JBool b -> Right b
  other -> Left ("expected a boolean, got " <> describe other)

list :: Decoder a -> Decoder [a]
list decodeItem = \case
  JArray items -> traverse decodeItem items
  other -> Left ("expected an array, got " <> describe other)

object :: Decoder [(Text, Json)]
object = \case
  JObject pairs -> Right pairs
  other -> Left ("expected an object, got " <> describe other)

-- | A string from a closed set of words, e.g. a status.
vocabulary :: (Text -> Maybe a) -> Decoder a
vocabulary parseWord json = do
  word <- text json
  maybe (Left ("unknown value \"" <> word <> "\"")) Right (parseWord word)

-- | A required object field; the error names the field.
field :: Text -> Decoder a -> [(Text, Json)] -> Either Text a
field key decode pairs = case lookup key pairs of
  Nothing -> Left ("missing field '" <> key <> "'")
  Just v -> first (\e -> "field '" <> key <> "': " <> e) (decode v)

-- | An optional object field: absent and @null@ both give 'Nothing'.
optionalField :: Text -> Decoder a -> [(Text, Json)] -> Either Text (Maybe a)
optionalField key decode pairs = case lookup key pairs of
  Nothing -> Right Nothing
  Just JNull -> Right Nothing
  Just v -> first (\e -> "field '" <> key <> "': " <> e) (Just <$> decode v)

describe :: Json -> Text
describe = T.take 60 . encodeJson
