#!/usr/bin/env python3
"""One-shot data hygiene over the company DB:

1. Normalize the free-text `remote` field — collapse format-equivalent values
   (e.g. "US based" / "Yes (US-based)" -> "Yes (US)"), map non-signal junk
   ("?", "Maybe") to "". Region detail is preserved, just consistently formatted.
2. Backfill a leading flag emoji on `locations` that lack one (via flags.py).

Re-runnable and idempotent. Only edits these two fields.
"""
import db
import flags

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

        locs = r.get("locations") or []
        new = flags.flag_all(locs)
        if new != locs:
            locs_flagged += sum(1 for a, b in zip(locs, new) if a != b)
            r["locations"] = new
            changed = True

        if changed:
            db.save(p.stem, r)

    print(f"remote normalized: {remote_changed}; locations flagged: {locs_flagged}")


if __name__ == "__main__":
    main()
