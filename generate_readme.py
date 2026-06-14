#!/usr/bin/env python3
"""Generate README.md from the per-company database.

Source of truth: the ``companies/*.md`` files (see db.py). Only companies with
``listed == True`` appear in the README table — i.e. commercial Earth
Observation companies that are active and have a careers page (set by
classify.py). Acquired / non-EO / reseller / consultancy companies stay in the
database but are excluded from the public table.

Run: ``python generate_readme.py``
"""
from pathlib import Path

import db

INTRO_PATH = Path("intro.md")
README_PATH = Path("README.md")

HEIGHT = 25

# link-dict key -> icon image (rendered in the Business / Social columns)
I_BUSINESS = {
    "crunchbase": "https://i.imgur.com/H3e6fly.png",
    "spac": "https://i.imgur.com/BjJ1vkt.png",
}
I_SOCIALS = {
    "twitter": "https://i.imgur.com/d4HTDdM.png",
    "youtube": "https://i.imgur.com/P1O5Rjh.png",
    "github": "https://i.imgur.com/5rpIT2Z.png",
    "linkedin": "https://i.imgur.com/SSBwtJu.png",
}

HIDE_REMOTE = {"", "No", "No jobs"}


def make_icons(links: dict, icon_links: dict) -> str:
    return "".join(
        f"""<a href="{links[key]}"><img src={src} height={HEIGHT}></a>"""
        for key, src in icon_links.items() if links.get(key)
    )


def row(rec: dict) -> dict:
    links = rec.get("links") or {}
    name = f"""<a href="{rec['website']}">{rec['name']}</a>"""

    careers = rec.get("careers_urls") or []
    jobs = "".join(
        f"""<a href="{url}">[{i}]</a>"""
        for i, url in enumerate(careers, 1)
    )

    locations = "<br />".join(rec.get("locations") or [])

    remote = rec.get("remote", "")
    remote = "" if remote in HIDE_REMOTE else remote

    return {
        "Name": name,
        "Description": rec.get("description", ""),
        "Jobs": jobs,
        "Locations": locations,
        "Remote": remote,
        "Social": make_icons(links, I_SOCIALS),
        "Business": make_icons(links, I_BUSINESS),
    }


COLUMNS = ["Name", "Description", "Jobs", "Locations", "Remote", "Social", "Business"]


def to_markdown_minimal(rows: list) -> str:
    """Render a left-aligned pipe table with minimal-width cells.

    Unlike padded tables (which pad every column to its widest cell), this keeps
    each row independent: changing one cell only changes that row's line, so
    refresh diffs stay row-local and reviewable. GitHub renders this identically.
    """
    lines = [
        "| " + " | ".join(COLUMNS) + " |",
        "|" + "|".join([":---"] * len(COLUMNS)) + "|",
    ]
    for r in rows:
        lines.append("| " + " | ".join(str(r[c]) for c in COLUMNS) + " |")
    return "\n".join(lines)


def main() -> None:
    recs = [r for r in db.load_all() if r.get("listed")]
    recs.sort(key=lambda r: r["name"].lower())
    rows = [row(r) for r in recs]

    intro = INTRO_PATH.read_text()
    README_PATH.write_text(intro + to_markdown_minimal(rows) + "\n")
    print(f"Wrote {README_PATH} ({len(rows)} companies)")


if __name__ == "__main__":
    main()
