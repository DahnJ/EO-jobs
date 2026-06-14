#!/usr/bin/env python3
"""Generate README.md from the EO companies CSV.

Source of truth: ``earth-observation-jobs - Companies.csv``.
Headless replacement for the old process-eo-companies.ipynb notebook.

Run: ``python generate_readme.py``
"""
from pathlib import Path
from typing import Dict

import pandas as pd

CSV_PATH = Path("earth-observation-jobs - Companies.csv")
INTRO_PATH = Path("intro.md")
README_PATH = Path("README.md")

HEIGHT = 25

I_BUSINESS = {
    "Crunchbase": "https://i.imgur.com/H3e6fly.png",
    "SPAC": "https://i.imgur.com/BjJ1vkt.png",
}
I_SOCIALS = {
    "Twitter": "https://i.imgur.com/d4HTDdM.png",
    "Youtube": "https://i.imgur.com/P1O5Rjh.png",
    "Github": "https://i.imgur.com/5rpIT2Z.png",
    "Linkedin": "https://i.imgur.com/SSBwtJu.png",
}

COLUMNS = [
    "Name", "Description", "Website", "Jobs site", "Jobs 2", "Locations",
    "Crunchbase", "Remote", "Linkedin", "Twitter", "SPAC", "Github", "Youtube",
]
NA_VALUES = ["?", "None?", "x"]


def make_icons(row: pd.Series, icon_links: Dict[str, str]) -> str:
    icons = [
        f"""<a href="{row[name]}"><img src={src} height={HEIGHT}></a>""" if row[name] else ""
        for name, src in icon_links.items()
    ]
    return "".join(icons)


def process(row: pd.Series) -> pd.Series:
    name = f"""<a href="{row['Website']}">{row['Name']}</a>"""
    description = row["Description"]

    jobs = f"""<a href="{row['Jobs site']}">[1]</a>""" if row["Jobs site"] else ""
    jobs += f"""<a href="{row['Jobs 2']}">[2]</a>""" if row["Jobs 2"] else ""

    locations = f"""{row['Locations'].replace('|', '<br />')}"""

    remote = row["Remote"] if row["Remote"] not in ["No", "No jobs"] else ""

    social = make_icons(row, I_SOCIALS)
    business = make_icons(row, I_BUSINESS)

    return pd.Series({
        "Name": name,
        "Description": description,
        "Jobs": jobs,
        "Locations": locations,
        "Remote": remote,
        "Social": social,
        "Business": business,
    })


def main() -> None:
    df = pd.read_csv(CSV_PATH, usecols=COLUMNS, na_values=NA_VALUES)
    df = df.iloc[df["Name"].str.lower().argsort()]
    result = df.fillna("").apply(process, axis=1)

    intro = INTRO_PATH.read_text()
    md = intro + result.to_markdown(index=False)
    README_PATH.write_text(md)
    print(f"Wrote {README_PATH} ({len(df)} companies)")


if __name__ == "__main__":
    main()
