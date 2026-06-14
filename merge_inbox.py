#!/usr/bin/env python3
"""Apply verified company records from companies/_inbox/*.json into the DB.

This is the single entry point for both refreshing existing companies and
adding newly discovered ones — verification subagents write JSON here, this
merges it in.

Each inbox record has:
  slug, name, status, website, careers_url, locations, remote,
  remote_evidence, description, note

For each record: if companies/<slug>.md exists, update its non-empty verified
fields; otherwise create a new file (source defaults to the --source value).
The agent's `note` is appended to the body with a dated stamp. `last_checked`
is stamped with today's date. `type`/`listed` are NOT set here — run
classify.py afterwards.

Usage:
  python merge_inbox.py [--source "discovery-sweep 2026-06"]
"""
import argparse
import datetime
import json

import db

INBOX = db.DB / "_inbox"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default="discovery-sweep",
                    help="source tag for NEWLY created files")
    args = ap.parse_args()
    today = datetime.date.today().isoformat()

    created, updated, skipped = [], [], []
    for f in sorted(INBOX.glob("*.json")):
        for r in json.load(f.open()):
            slug = (r.get("slug") or "").strip()
            if not slug:
                skipped.append(r.get("name", "?"))
                continue
            path = db.DB / f"{slug}.md"
            if path.exists():
                rec = db.parse(path.read_text())
                is_new = False
            else:
                rec = {"name": r.get("name", slug), "status": "unknown",
                       "website": "", "careers_urls": [], "locations": [],
                       "remote": "", "remote_evidence": "", "description": "",
                       "satellites": "", "category": "", "listed": False,
                       "links": {}, "source": args.source, "body": ""}
                is_new = True

            # never downgrade a known status to "unknown" (e.g. a fetch failure)
            if r.get("status") and not (r["status"] == "unknown" and rec.get("status") not in ("", "unknown", None)):
                rec["status"] = r["status"]
            if r.get("website"):
                rec["website"] = r["website"]
            cu = (r.get("careers_url") or "").strip()
            if cu:
                rec["careers_urls"] = [cu]
            if r.get("locations"):
                rec["locations"] = r["locations"]
            if r.get("remote"):
                rec["remote"] = r["remote"]
            if r.get("remote_evidence"):
                rec["remote_evidence"] = r["remote_evidence"]
            if r.get("description"):
                rec["description"] = r["description"]
            # union social/business links without clobbering existing ones
            for k, v in (r.get("links") or {}).items():
                if v:
                    rec.setdefault("links", {}).setdefault(k, v)
            rec["last_checked"] = today

            note = (r.get("note") or "").strip()
            if note:
                stamp = f"[{args.source} {today}] {note}"
                body = rec.get("body", "")
                rec["body"] = (body + "\n\n" + stamp).strip() if body else stamp

            db.save(slug, rec)
            (created if is_new else updated).append(slug)

    print(f"created {len(created)}, updated {len(updated)}, skipped {len(skipped)}")
    if updated:
        print("updated:", ", ".join(sorted(updated)))
    if skipped:
        print("skipped (no slug):", ", ".join(skipped))


if __name__ == "__main__":
    main()
