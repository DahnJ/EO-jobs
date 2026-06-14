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


if __name__ == "__main__":
    from collections import Counter
    cos = load_all()
    print(f"loaded {len(cos)} companies")
    print("by status:", dict(Counter(c["status"] for c in cos)))
    print("by source:", dict(Counter(c["source"] for c in cos)))
    print("listed (README candidates):", sum(1 for c in cos if c["listed"]))
