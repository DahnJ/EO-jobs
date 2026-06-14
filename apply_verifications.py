#!/usr/bin/env python3
"""Apply subagent verification results to company files.

Input: a JSON array of results, each:
  {"slug","status","website","careers_url","locations","remote",
   "remote_evidence","description","note"}
Empty/missing fields are left unchanged. `note` is appended to the body.
`last_checked` is stamped; if status resolved away from "unknown" the row is
left for the README-filter step (listed is not touched here).
"""
import json
import sys
from pathlib import Path

import db


def main() -> None:
    results = json.loads(Path(sys.argv[1]).read_text())
    applied, missing = 0, []
    for r in results:
        slug = r.get("slug")
        path = db.DB / f"{slug}.md"
        if not path.exists():
            missing.append(slug)
            continue
        rec = db.parse(path.read_text())
        if r.get("status"):
            rec["status"] = r["status"]
        if r.get("website"):
            rec["website"] = r["website"]
        if r.get("careers_url"):
            rec["careers_urls"] = [r["careers_url"]]
        if r.get("locations"):
            rec["locations"] = r["locations"]
        if r.get("remote"):
            rec["remote"] = r["remote"]
        if r.get("remote_evidence"):
            rec["remote_evidence"] = r["remote_evidence"]
        if r.get("description"):
            rec["description"] = r["description"]
        rec["last_checked"] = "2026-06-14"
        note = r.get("note", "").strip()
        if note:
            body = rec.get("body", "")
            rec["body"] = (body + "\n\n" + note).strip() if body else note
        db.save(slug, rec)
        applied += 1
    print(f"applied {applied}; missing slugs: {missing or 'none'}")


if __name__ == "__main__":
    main()
