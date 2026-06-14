#!/usr/bin/env python3
"""One-shot data hygiene over the company DB:

1. Normalize the free-text `remote` field — collapse format-equivalent values
   (e.g. "US based" / "Yes (US-based)" -> "Yes (US)"), map non-signal junk
   ("?", "Maybe") to "". Region detail is preserved, just consistently formatted.
2. Backfill a leading country/region flag emoji on `locations` entries that lack
   one, by detecting the country (or a known city / region word) in the string.

Re-runnable and idempotent. Only edits these two fields.
"""
import db

# old value -> canonical value. Anything not listed is left unchanged.
REMOTE_MAP = {
    "US based": "Yes (US)", "US-based": "Yes (US)", "Yes (US-based)": "Yes (US)",
    "Yes (US-based?)": "Yes (US)", "Yes (~US?)": "Yes (US)", "US resident": "Yes (US)",
    "Canada-based": "Yes (Canada)", "Australia-based": "Yes (Australia)",
    "Yes (UK-based?)": "Yes (UK)", "Yes (UK-elligible)": "Yes (UK)",
    "Yes (France-based?)": "Yes (France)",
    "~Yes": "Yes",
    "Some roles remote": "Hybrid", "Some": "Hybrid", "Occasionally": "Hybrid",
    "No (Partial)": "Hybrid",
    "Maybe": "", "?": "",
    "Yes (UK, Luxembroug, France, Belgium, Germany)":
        "Yes (UK, Luxembourg, France, Belgium, Germany)",
}

# Detected country/city/region keyword (lowercased substring) -> flag.
# Order matters: first match wins, so list more specific tokens first.
COUNTRY = [
    ("united states", "🇺🇸"), ("usa", "🇺🇸"), ("u.s.", "🇺🇸"),
    ("united kingdom", "🇬🇧"), ("netherlands", "🇳🇱"), ("germany", "🇩🇪"),
    ("france", "🇫🇷"), ("switzerland", "🇨🇭"), ("canada", "🇨🇦"),
    ("china", "🇨🇳"), ("india", "🇮🇳"), ("south korea", "🇰🇷"),
    ("singapore", "🇸🇬"), ("australia", "🇦🇺"), ("kenya", "🇰🇪"),
    ("mexico", "🇲🇽"), ("japan", "🇯🇵"), ("spain", "🇪🇸"), ("italy", "🇮🇹"),
    ("sweden", "🇸🇪"), ("finland", "🇫🇮"), ("norway", "🇳🇴"),
    ("denmark", "🇩🇰"), ("ireland", "🇮🇪"), ("brazil", "🇧🇷"),
    ("israel", "🇮🇱"), ("estonia", "🇪🇪"),
]
# City / state / region word -> flag, for strings that name no country.
CITY = [
    ("london", "🇬🇧"), ("didcot", "🇬🇧"), ("skipton", "🇬🇧"),
    ("sydney", "🇦🇺"),
    ("seattle", "🇺🇸"), ("boston", "🇺🇸"), ("berkeley", "🇺🇸"),
    ("denver", "🇺🇸"), ("san mateo", "🇺🇸"), ("north potomac", "🇺🇸"),
    ("bozeman", "🇺🇸"), ("lafayette", "🇺🇸"), ("montana", "🇺🇸"),
    ("california", "🇺🇸"), ("colorado", "🇺🇸"), ("seoul", "🇰🇷"),
    ("amsterdam", "🇳🇱"), ("zwolle", "🇳🇱"), ("hamburg", "🇩🇪"),
    ("paris", "🇫🇷"), ("hyderabad", "🇮🇳"), ("changchun", "🇨🇳"),
    ("vancouver", "🇨🇦"), ("halifax", "🇨🇦"), ("calgary", "🇨🇦"),
    ("zurich", "🇨🇭"), ("zürich", "🇨🇭"),
]
REGION = [
    ("asia pacific", "🌏"), ("asia", "🌏"), ("europe", "🌍"),
    ("multiple continents", "🌐"), ("global", "🌐"), ("world", "🌐"),
    ("many locations", "🌐"), ("many countries", "🌐"),
]
HAS_FLAG = "🇦🇧🇨🇩🇪🇫🇬🇭🇮🇯🇰🇱🇲🇳🇴🇵🇶🇷🇸🇹🇺🇻🇼🇽🇾🇿🌍🌏🌎🌐"


def flag_for(loc: str):
    low = loc.lower()
    for table in (COUNTRY, CITY, REGION):
        for kw, fl in table:
            if kw in low:
                return fl
    return None


def main() -> None:
    remote_changed = locs_flagged = 0
    for p in sorted(db.DB.glob("*.md")):
        r = db.parse(p.read_text())
        changed = False

        rv = r.get("remote", "")
        if rv in REMOTE_MAP and REMOTE_MAP[rv] != rv:
            r["remote"] = REMOTE_MAP[rv]
            remote_changed += 1
            changed = True

        new_locs = []
        for loc in (r.get("locations") or []):
            if any(ch in HAS_FLAG for ch in loc):
                new_locs.append(loc)
                continue
            fl = flag_for(loc)
            if fl:
                new_locs.append(f"{fl} {loc}")
                locs_flagged += 1
                changed = True
            else:
                new_locs.append(loc)
        if changed:
            r["locations"] = new_locs
            db.save(p.stem, r)  # use the actual filename slug

    print(f"remote normalized: {remote_changed}; locations flagged: {locs_flagged}")


if __name__ == "__main__":
    main()
