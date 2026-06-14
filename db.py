#!/usr/bin/env python3
"""Load the per-company database.

Each companies/<slug>.md file has JSON-valued YAML frontmatter (every value is
valid JSON) plus a free-text body. Parsing therefore needs no YAML library:
split the frontmatter block and json.loads each value.
"""
import json
from pathlib import Path

DB = Path("companies")


def parse(text: str) -> dict:
    if not text.startswith("---"):
        raise ValueError("missing frontmatter")
    _, fm, body = text.split("---", 2)
    rec = {}
    for line in fm.strip().splitlines():
        if not line.strip():
            continue
        key, _, raw = line.partition(": ")
        rec[key.strip()] = json.loads(raw)
    rec["body"] = body.strip()
    return rec


def load_all() -> list:
    return [parse(p.read_text()) for p in sorted(DB.glob("*.md"))]


FIELD_ORDER = ["name", "status", "website", "careers_urls", "locations",
               "remote", "remote_evidence", "remote_confidence", "description",
               "satellites", "category", "listed", "links", "source",
               "last_checked"]


def dump(rec: dict) -> str:
    """Serialize a record back to file text (frontmatter values as JSON)."""
    body = rec.get("body", "")
    keys = [k for k in FIELD_ORDER if k in rec] + \
           [k for k in rec if k not in FIELD_ORDER and k != "body"]
    lines = ["---"] + [f"{k}: {json.dumps(rec[k], ensure_ascii=False)}" for k in keys] + ["---"]
    text = "\n".join(lines) + "\n"
    if body.strip():
        text += "\n" + body.strip() + "\n"
    return text


def save(slug: str, rec: dict) -> None:
    (DB / f"{slug}.md").write_text(dump(rec))


if __name__ == "__main__":
    from collections import Counter
    cos = load_all()
    print(f"loaded {len(cos)} companies")
    print("by status:", dict(Counter(c["status"] for c in cos)))
    print("by source:", dict(Counter(c["source"] for c in cos)))
    print("listed (README candidates):", sum(1 for c in cos if c["listed"]))
