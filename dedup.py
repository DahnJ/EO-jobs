#!/usr/bin/env python3
"""Merge known duplicate company entries, recorded in known_duplicates.json.

Each group names the slugs that are the same real company and which to `keep`.
For each group: union the useful fields from the dropped entries into the kept
one (careers_urls, locations, links — never overwriting a non-empty scalar on
the keeper), append a provenance note, then delete the dropped files.

The JSON is the persistent record of dedup decisions ("mark them for next time")
and feeds the discovery B1 dedup: the dropped names are known aliases.

Re-runnable: groups whose dropped files are already gone are skipped.

Usage: python dedup.py
"""
import json

import db

GROUPS = json.loads((db.DB.parent / "known_duplicates.json").read_text())


def alias_slugs() -> set:
    """Slugs that have been folded away — for discovery dedup to also skip."""
    out = set()
    for g in GROUPS:
        out.update(s for s in g["slugs"] if s != g["keep"])
    return out


def main() -> None:
    merged = 0
    for g in GROUPS:
        keep = g["keep"]
        kp = db.DB / f"{keep}.md"
        if not kp.exists():
            print(f"skip {g['slugs']}: keeper {keep} missing")
            continue
        krec = db.parse(kp.read_text())
        dropped = []
        for s in g["slugs"]:
            if s == keep:
                continue
            dp = db.DB / f"{s}.md"
            if not dp.exists():
                continue
            drec = db.parse(dp.read_text())
            # union list/dict fields without clobbering the keeper's scalars
            for u in (drec.get("careers_urls") or []):
                if u not in krec.setdefault("careers_urls", []):
                    krec["careers_urls"].append(u)
            for loc in (drec.get("locations") or []):
                if loc not in krec.setdefault("locations", []):
                    krec["locations"].append(loc)
            for k, v in (drec.get("links") or {}).items():
                krec.setdefault("links", {}).setdefault(k, v)
            dp.unlink()
            dropped.append(s)
        if dropped:
            note = f"[dedup] merged duplicate(s) {', '.join(dropped)} — {g['reason']}"
            body = krec.get("body", "")
            krec["body"] = (body + "\n\n" + note).strip() if body else note
            db.save(keep, krec)
            merged += 1
            print(f"merged {dropped} -> {keep}")
    print(f"done: {merged} group(s) merged")


if __name__ == "__main__":
    main()
