#!/usr/bin/env python3
"""Prepend a flag emoji to a location string.

Locations in the DB must carry a leading flag (or globe for regions/remote).
Flags are derived from the country's ISO-3166 alpha-2 code via regional-indicator
characters, so adding a country only means adding one map entry — not hunting down
an emoji. Used by both fixup_data.py and merge_inbox.py so any write stays flagged.
"""

def iso_to_flag(iso2: str) -> str:
    return "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in iso2.upper())


# country name / common abbreviation -> ISO alpha-2
COUNTRY = {
    "united states": "US", "usa": "US", "u.s.": "US", "u.s.a": "US", "us": "US",
    "united kingdom": "GB", "uk": "GB", "u.k.": "GB", "england": "GB",
    "scotland": "GB", "wales": "GB", "northern ireland": "GB", "britain": "GB",
    "france": "FR", "germany": "DE", "netherlands": "NL", "the netherlands": "NL",
    "spain": "ES", "italy": "IT", "portugal": "PT", "belgium": "BE",
    "luxembourg": "LU", "switzerland": "CH", "austria": "AT", "ireland": "IE",
    "sweden": "SE", "norway": "NO", "denmark": "DK", "finland": "FI",
    "iceland": "IS", "poland": "PL", "czech republic": "CZ", "czechia": "CZ",
    "slovakia": "SK", "slovenia": "SI", "hungary": "HU", "romania": "RO",
    "bulgaria": "BG", "greece": "GR", "croatia": "HR", "serbia": "RS",
    "ukraine": "UA", "belarus": "BY", "estonia": "EE", "latvia": "LV",
    "lithuania": "LT", "russia": "RU", "turkey": "TR", "türkiye": "TR",
    "cyprus": "CY", "malta": "MT", "uzbekistan": "UZ", "kazakhstan": "KZ",
    "canada": "CA", "mexico": "MX", "brazil": "BR", "argentina": "AR",
    "chile": "CL", "colombia": "CO", "peru": "PE", "uruguay": "UY",
    "ecuador": "EC", "bolivia": "BO", "china": "CN", "japan": "JP",
    "south korea": "KR", "korea": "KR", "india": "IN", "singapore": "SG",
    "taiwan": "TW", "hong kong": "HK", "indonesia": "ID", "malaysia": "MY",
    "thailand": "TH", "vietnam": "VN", "philippines": "PH", "pakistan": "PK",
    "bangladesh": "BD", "sri lanka": "LK", "australia": "AU",
    "new zealand": "NZ", "israel": "IL", "uae": "AE",
    "united arab emirates": "AE", "saudi arabia": "SA", "qatar": "QA",
    "kuwait": "KW", "bahrain": "BH", "oman": "OM", "jordan": "JO",
    "lebanon": "LB", "egypt": "EG", "south africa": "ZA", "kenya": "KE",
    "nigeria": "NG", "ghana": "GH", "tanzania": "TZ", "uganda": "UG",
    "rwanda": "RW", "ethiopia": "ET", "morocco": "MA", "tunisia": "TN",
    "senegal": "SN", "azerbaijan": "AZ", "georgia": "GE", "armenia": "AM",
    "iraq": "IQ", "iran": "IR", "qatar ": "QA",
}

# city / US-state / region word -> ISO alpha-2, for strings naming no country.
CITY = {
    # UK
    "london": "GB", "edinburgh": "GB", "glasgow": "GB", "bristol": "GB",
    "oxford": "GB", "cambridge": "GB", "reading": "GB", "guildford": "GB",
    "plymouth": "GB", "didcot": "GB", "harwell": "GB", "skipton": "GB",
    "leicester": "GB", "belfast": "GB", "musselburgh": "GB", "sywell": "GB",
    "northamptonshire": "GB",
    # US cities/states
    "seattle": "US", "boston": "US", "berkeley": "US", "denver": "US",
    "houston": "US", "midland": "US", "austin": "US", "madison": "US",
    "santa fe": "US", "washington": "US", "san mateo": "US", "bozeman": "US",
    "lafayette": "US", "north potomac": "US", "san francisco": "US",
    "new york": "US", "montana": "US", "california": "US", "colorado": "US",
    "texas": "US", "wi": "US", "tx": "US", "ca": "US", "wa": "US", "co": "US",
    "ny": "US", "ma": "US",
    # other cities
    "sydney": "AU", "melbourne": "AU", "seoul": "KR", "tokyo": "JP",
    "singapore": "SG", "amsterdam": "NL", "zwolle": "NL", "hamburg": "DE",
    "munich": "DE", "berlin": "DE", "paris": "FR", "toulouse": "FR",
    "hyderabad": "IN", "bangalore": "IN", "bengaluru": "IN", "changchun": "CN",
    "vancouver": "CA", "halifax": "CA", "calgary": "CA", "toronto": "CA",
    "zurich": "CH", "zürich": "CH", "vienna": "AT", "graz": "AT",
    "warsaw": "PL", "wrocław": "PL", "wroclaw": "PL", "kraków": "PL",
    "krakow": "PL", "gliwice": "PL", "piaseczno": "PL", "brussels": "BE",
    "liege": "BE", "liège": "BE", "mont-saint-guibert": "BE", "athens": "GR",
    "lisbon": "PT", "porto": "PT", "brno": "CZ", "prague": "CZ",
    "sofia": "BG", "ljubljana": "SI", "bratislava": "SK", "tashkent": "UZ",
    "minsk": "BY", "lagos": "NG", "abuja": "NG", "johannesburg": "ZA",
    "nairobi": "KE", "buenos aires": "AR", "ayacucho": "PE",
    "esch-sur-alzette": "LU", "abu dhabi": "AE", "dubai": "AE",
}

REGION = {
    "remote": "🌐", "global": "🌐", "worldwide": "🌐", "anywhere": "🌐",
    "world": "🌐", "many locations": "🌐", "many countries": "🌐",
    "multiple continents": "🌐", "europe": "🌍", "asia pacific": "🌏",
    "asia": "🌏", "africa": "🌍",
}

_FLAG_CHARS = "🇦🇧🇨🇩🇪🇫🇬🇭🇮🇯🇰🇱🇲🇳🇴🇵🇶🇷🇸🇹🇺🇻🇼🇽🇾🇿🌍🌏🌎🌐"


def has_flag(loc: str) -> bool:
    return any(ch in _FLAG_CHARS for ch in loc)


def _detect(loc: str):
    low = loc.lower().strip()
    # last comma/semicolon-separated token first (most reliable: the country)
    tokens = [t.strip() for t in low.replace(";", ",").split(",") if t.strip()]
    for tok in reversed(tokens):
        if tok in COUNTRY:
            return iso_to_flag(COUNTRY[tok])
        if tok in CITY:
            return iso_to_flag(CITY[tok])
    for kw, fl in REGION.items():
        if kw in low:
            return fl
    # fallback: any country name appearing anywhere
    for name, iso in COUNTRY.items():
        if len(name) > 3 and name in low:
            return iso_to_flag(iso)
    for city, iso in CITY.items():
        if len(city) > 3 and city in low:
            return iso_to_flag(iso)
    return None


def add_flag(loc: str) -> str:
    """Return loc with a leading flag/globe; unchanged if one is present or none fits."""
    if not loc or has_flag(loc):
        return loc
    fl = _detect(loc)
    return f"{fl} {loc}" if fl else loc


def flag_all(locations: list) -> list:
    return [add_flag(l) for l in (locations or [])]


if __name__ == "__main__":
    import db
    fixed = miss = 0
    misses = []
    for p in sorted(db.DB.glob("*.md")):
        r = db.parse(p.read_text())
        locs = r.get("locations") or []
        new = flag_all(locs)
        if new != locs:
            r["locations"] = new
            db.save(p.stem, r)
            fixed += sum(1 for a, b in zip(locs, new) if a != b)
        for l in new:
            if not has_flag(l):
                miss += 1
                misses.append(l)
    print(f"flagged {fixed} locations; still unflagged: {miss}")
    if misses:
        print("unmatched:", sorted(set(misses)))
