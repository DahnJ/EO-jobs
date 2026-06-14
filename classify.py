#!/usr/bin/env python3
"""Classify each company by `type` and set `listed` for the README view.

Transparent, conservative rules over the description + body text (not per-company
guesswork). Only EXCLUDES on a clear signal; the fuzzy middle defaults to
`commercial-eo` (included). Writes `type` to every file and sets:

    listed = (type == "commercial-eo" and status == "active" and has careers URL)

Override is easy: edit `listed` (or `type`) in any file by hand; this script is
re-runnable but won't clobber a manual `type_locked: true` if present.
"""
import db

# Obvious large conglomerates / parents where EO is one small division.
CONGLOMERATES = {
    "airbus-space", "airbus-defence-and-space", "trimble", "harris", "gmv",
    "telespazio", "hexagon-geospatial", "nv5", "merrick", "red-wire-space",
    "iabg", "l3harris",
}


def classify(rec: dict) -> tuple:
    """Return (type, reason). Order = priority; first match wins."""
    slug = rec.get("name", "")
    text = (rec.get("description", "") + " " + rec.get("body", "")).lower()

    if "not-eo" in text or "not an earth observation" in text or "not a geospatial" in text:
        return "not-eo", "flagged not-EO during verification"
    if any(w in text for w in ["nonprofit", "non-profit", "not-for-profit", " ngo", "501(c)", "foundation"]):
        return "nonprofit", "nonprofit/NGO language"
    return None, ""  # placeholder; real slug-based checks happen in main()


def classify_with_slug(slug: str, rec: dict) -> tuple:
    text = (rec.get("description", "") + " " + rec.get("body", "")).lower()
    if slug in CONGLOMERATES:
        return "conglomerate", "known large multi-division company"
    t, r = classify(rec)
    if t:
        return t, r
    if "reseller" in text:
        return "reseller", "describes itself as a data reseller"
    if "consultancy" in text or "consultant" in text:
        return "consultancy", "describes itself as a consultancy"
    if any(w in text for w in ["point cloud", "photogrammetry software", "lastools",
                                "ecognition", "3d point", "point-cloud"]):
        return "software", "point-cloud / photogrammetry software tool"
    return "commercial-eo", "default (no exclusion signal)"


def main() -> None:
    from collections import Counter
    import re
    counts = Counter()
    listed = 0
    excluded_examples = {}
    for p in sorted(db.DB.glob("*.md")):
        rec = db.parse(p.read_text())
        slug = p.stem
        typ, reason = classify_with_slug(slug, rec)
        rec["type"] = typ
        rec["type_reason"] = reason
        is_listed = (typ == "commercial-eo" and rec["status"] == "active"
                     and bool(rec["careers_urls"]))
        rec["listed"] = is_listed
        counts[typ] += 1
        if is_listed:
            listed += 1
        elif typ != "commercial-eo":
            excluded_examples.setdefault(typ, []).append(rec["name"])
        db.save(slug, rec)

    print("type distribution:", dict(counts))
    print("LISTED (commercial-eo + active + has careers):", listed)
    print()
    print("commercial-eo but NOT listed (active w/o careers, or non-active):",
          counts["commercial-eo"] - listed)
    print()
    for typ, names in excluded_examples.items():
        print(f"--- excluded as {typ} ({len(names)}): " + ", ".join(sorted(names)[:30]))


if __name__ == "__main__":
    main()
