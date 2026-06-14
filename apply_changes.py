#!/usr/bin/env python3
"""Apply field changes to the EO companies CSV, preserving its exact format.

Usage:
    python apply_changes.py changes.json

``changes.json`` maps company Name -> {Column: new value, ...}. A Name not
already present is appended as a NEW company row (other columns left blank).

Format is preserved so diffs stay row-local: CRLF line endings, no trailing
newline, fixed column order. Pair with ``generate_readme.py`` to regenerate the
README after applying.
"""
import json
import sys
from pathlib import Path

import pandas as pd

CSV = Path("earth-observation-jobs - Companies.csv")
COLS = [
    "Name", "Description", "Satellites", "Website", "Jobs site", "Jobs 2",
    "Locations", "Remote", "Crunchbase", "Linkedin", "Twitter", "SPAC",
    "Github", "Youtube", "Stocks", "Medium", "Instagram", "Notes",
]


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: python apply_changes.py changes.json")
    changes = json.loads(Path(sys.argv[1]).read_text())

    df = pd.read_csv(CSV, dtype=str, keep_default_na=False).set_index("Name")

    updated, added = [], []
    for name, fields in changes.items():
        bad = [c for c in fields if c not in COLS or c == "Name"]
        if bad:
            sys.exit(f"Unknown/disallowed column(s) {bad} for {name!r}")
        if name not in df.index:
            df.loc[name] = ""
            added.append(name)
        else:
            updated.append(name)
        for col, val in fields.items():
            df.loc[name, col] = val

    df = df.reset_index()[COLS]
    out = df.to_csv(index=False, lineterminator="\r\n").rstrip("\r\n")
    CSV.write_text(out)
    print(f"Updated {len(updated)} companies; added {len(added)} new "
          f"({', '.join(added) if added else 'none'})")


if __name__ == "__main__":
    main()
