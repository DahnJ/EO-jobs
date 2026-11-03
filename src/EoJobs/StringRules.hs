-- | The string rules the data files were written under: which characters count
-- as whitespace for trimming (not Haskell's 'isSpace'), and string order and
-- length counted in UTF-16 code units. Keeps rewritten files byte-identical.
module EoJobs.StringRules
  ( trim
  , isBlank
  , utf16Order
  , takeUtf16
  ) where

import Data.Char (ord)
import Data.Text (Text)
import qualified Data.Text as T

-- | What 'trim' strips: Unicode space separators except the non-breaking ones,
-- plus tab, newline, vertical tab, form feed, carriage return and U+001C..U+001F.
isTrimmable :: Char -> Bool
isTrimmable c
  | c `elem` ['\x00A0', '\x2007', '\x202F'] = False
  | c `elem` ['\t', '\n', '\x0B', '\f', '\r'] = True
  | c >= '\x1C' && c <= '\x1F' = True
  | otherwise =
      c == ' ' || c == '\x1680' || (c >= '\x2000' && c <= '\x200A')
        || c `elem` ['\x2028', '\x2029', '\x205F', '\x3000']

-- | Strip leading and trailing whitespace.
trim :: Text -> Text
trim = T.dropAround isTrimmable

-- | Empty or only whitespace.
isBlank :: Text -> Bool
isBlank = T.all isTrimmable

-- | Sort key that orders strings by UTF-16 code units.
utf16Order :: Text -> [Int]
utf16Order = concatMap utf16Units . T.unpack

utf16Units :: Char -> [Int]
utf16Units c
  | n < 0x10000 = [n]
  | otherwise = [0xD800 + (m `div` 0x400), 0xDC00 + (m `mod` 0x400)]
  where
    n = ord c
    m = n - 0x10000

-- | The first @n@ UTF-16 code units. A surrogate pair cut in half becomes @?@,
-- the replacement the original UTF-8 writer emitted for the lone half.
takeUtf16 :: Int -> Text -> Text
takeUtf16 limit = T.pack . go limit . T.unpack
  where
    go _ [] = []
    go remaining (c : rest)
      | width <= remaining = c : go (remaining - width) rest
      | remaining > 0 = "?"
      | otherwise = []
      where
        width = length (utf16Units c)
