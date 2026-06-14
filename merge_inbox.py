#!/usr/bin/env python3
"""Merge verified discovery records from companies/_inbox/*.json into the DB.

Each inbox record (from the discovery-sweep verification agents) has:
  slug, name, status, website, careers_url, locations, remote,
  remote_evidence, description, note

For each record: if companies/<slug>.md exists, update non-empty fields;
otherwise create a new file. New files get source "discovery-sweep 2026-06"
and listed=false (classify.py sets type/listed afterwards). The agent's `note`
is appended to the body. last_checked is stamped 2026-06-14.
"""
import json
import db

INBOX = db.DB / "_inbox"
CHECKED = "2026-06-14"
SOURCE = "discovery-sweep 2026-06"


def main() -> None:
    created, updated, skipped = [], [], []
    for f in sorted(INBOX.glob("disc_*.json")):
        for r in json.load(f.open()):
            slug = r.get("slug", "").strip()
            if not slug:
                skipped.append(r.get("name", "?"))
                continue
            path = db.DB / f"{slug}.md"
            if path.exists():
                rec = db.parse(path.read_text())
                is_new = False
            else:
                rec = {"name": r["name"], "status": "unknown", "website": "",
                       "careers_urls": [], "locations": [], "remote": "",
                       "remote_evidence": "", "description": "", "satellites": "",
                       "category": "", "listed": False, "links": {},
                       "source": SOURCE, "body": ""}
                is_new = True

            # apply non-empty verified fields
            if r.get("status"):
                rec["status"] = r["status"]
            if r.get("website"):
                rec["website"] = r["website"]
            cu = r.get("careers_url", "").strip()
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
            rec["last_checked"] = CHECKED

            note = r.get("note", "").strip()
            if note:
                body = rec.get("body", "")
                stamp = f"[discovery-sweep {CHECKED}] {note}"
                rec["body"] = (body + "\n\n" + stamp).strip() if body else stamp

            db.save(slug, rec)
            (created if is_new else updated).append(slug)

    print(f"created {len(created)}, updated {len(updated)}, skipped {len(skipped)}")
    if updated:
        print("updated (already in DB):", ", ".join(sorted(updated)))
    if skipped:
        print("skipped (no slug):", ", ".join(skipped))


if __name__ == "__main__":
    main()
