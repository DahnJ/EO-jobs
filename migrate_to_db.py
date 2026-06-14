#!/usr/bin/env python3
"""Seed the per-company database from the legacy CSV + the discovery Google Sheet.

Each company becomes one plain-text file at companies/<slug>.md with
JSON-valued YAML frontmatter (valid YAML, parseable without pyyaml) plus a
free-text body for history/evidence/provenance.

The database aims for FULL coverage — it keeps acquired/defunct/renamed
companies (tagged via `status`). The README is a curated view generated from it
later. This script is one-shot seeding; ongoing edits happen per-file.
"""
import json
import re
from pathlib import Path

import pandas as pd

OUT = Path("companies")
CSV = Path("earth-observation-jobs - Companies.csv")
SHEET = Path("/tmp/sheet.csv")

# Companies refreshed in this session's agent runs (last_checked = 2026-06-14)
CHECKED_2026_06 = {
    "Kayrros", "Pixxel", "Wyvern", "Albedo", "Satellogic", "Open Cosmos",
    "Muon Space", "GeoAlert", "Tensorflight", "Bluefield", "iQPS", "KatRisk",
    "Planet Observer", "Space Will", "Spacety", "Arturo", "Near Space Labs",
    "EarthDaily", "Orora Tech", "SkyFi", "GHGSAT", "SkyWatch", "Edgybees",
    "SatelliteVu", "Axelspace", "ICEYE", "Aerospacelab", "Airbus Space",
    "Alba Orbital", "Astraea", "AXA Climate", "CloudEO", "Farmers Edge",
    "Geocento",
}
# Status overrides from this session's findings (default is "active")
STATUS = {
    "Kayrros": "acquired", "Astraea": "acquired", "Arturo": "acquired",
    "Bluefield": "defunct", "Farmers Edge": "renamed",
}

LINK_COLS = ["Crunchbase", "Linkedin", "Twitter", "SPAC", "Github",
             "Youtube", "Stocks", "Medium", "Instagram"]


def slug(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s or "unnamed"


def domain(u: str) -> str:
    if not isinstance(u, str) or not u:
        return ""
    u = re.sub(r"^https?://", "", u.strip().lower()).replace("www.", "")
    return u.split("/")[0]


def write_company(rec: dict, body: str) -> str:
    """Emit one company file. Every frontmatter value is JSON (valid YAML)."""
    lines = ["---"]
    for k, v in rec.items():
        lines.append(f"{k}: {json.dumps(v, ensure_ascii=False)}")
    lines.append("---")
    text = "\n".join(lines) + "\n"
    if body.strip():
        text += "\n" + body.strip() + "\n"
    return text


def from_csv() -> tuple:
    df = pd.read_csv(CSV, dtype=str, keep_default_na=False)
    files = {}
    domains = {domain(w) for w in df["Website"] if domain(w)}
    for _, r in df.iterrows():
        name = r["Name"].strip()
        careers = [u for u in (r["Jobs site"], r["Jobs 2"]) if u and u != "?"]
        links = {c.lower(): r[c] for c in LINK_COLS if r[c] and r[c] not in ("?", "x")}
        rec = {
            "name": name,
            "status": STATUS.get(name, "active"),
            "website": r["Website"],
            "careers_urls": careers,
            "locations": [s.strip() for s in r["Locations"].split("|") if s.strip()],
            "remote": r["Remote"],
            "remote_evidence": "",
            "description": r["Description"],
            "satellites": r["Satellites"],
            "category": "",
            "listed": True,
            "links": links,
            "source": "original list",
            "last_checked": "2026-06-14" if name in CHECKED_2026_06 else "",
        }
        files[slug(name)] = write_company(rec, r["Notes"])
    return files, domains


def from_sheet(existing_slugs: set, existing_domains: set) -> dict:
    if not SHEET.exists():
        return {}
    df = pd.read_csv(SHEET, dtype=str, keep_default_na=False)
    eo = df[df["Category"].str.strip().str.lower() == "earth observation"]
    files = {}
    for _, r in eo.iterrows():
        name = r["Company"].strip()
        sl = slug(name)
        dom = domain(r.get("Website", ""))
        if not name or sl in existing_slugs or sl in files:
            continue  # dedupe vs CSV and within-sheet by name
        if dom and dom in existing_domains:
            continue  # dedupe vs CSV by website domain
        city, country = r.get("City", "").strip(), r.get("Country", "").strip()
        loc = country if (not city or city == country) else f"{city}, {country}"
        rec = {
            "name": name,
            "status": "unknown",
            "website": r.get("Website", ""),
            "careers_urls": [r["Careers URL"]] if r.get("Careers URL") else [],
            "locations": [loc] if loc else [],
            "remote": "",
            "remote_evidence": "",
            "description": r.get("Focus", ""),
            "satellites": "",
            "category": r.get("Category", ""),
            "listed": False,  # discovered, unverified — not in README until reviewed
            "links": {},
            "source": "google-sheet 2026-06",
            "last_checked": "",
        }
        aka = r.get("Notes (ex-name)", "")
        body = f"Discovered via the EO companies Google Sheet (2026-06); unverified." + (
            f" Ex-name/note: {aka}." if aka else "")
        files[sl] = write_company(rec, body)
    return files


def main() -> None:
    OUT.mkdir(exist_ok=True)
    csv_files, csv_domains = from_csv()
    sheet_files = from_sheet(set(csv_files), csv_domains)
    for sl, text in {**csv_files, **sheet_files}.items():
        (OUT / f"{sl}.md").write_text(text)
    print(f"Wrote {len(csv_files)} from CSV + {len(sheet_files)} from sheet "
          f"= {len(csv_files) + len(sheet_files)} company files in {OUT}/")


if __name__ == "__main__":
    main()
