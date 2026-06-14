#!/usr/bin/env python3
"""Set each company's `type` from agent judgment, and `listed` for the README.

Type is decided by a verification/classification agent (see the refresh-eo-jobs
skill) which reads each company's description and writes its verdicts to
companies/_inbox/class_*.json as [{slug, type, reason}]. This script applies
those verdicts, then sets:

    listed = (type == "commercial-eo" and status == "active" and has careers URL)

A small CONGLOMERATES safety net forces the obvious large multi-division parents
to `conglomerate` regardless of the agent. If no inbox files are present, the
script just recomputes `listed` from the existing `type` fields (so listing can
be refreshed after a hand-edit without re-running agents).

Run: ``python classify.py``
"""
import glob
import json
from collections import Counter

import db

# Large multi-division parents where EO is one small division — forced override.
CONGLOMERATES = {
    "airbus-space", "airbus-defence-and-space", "trimble", "harris", "gmv",
    "telespazio", "hexagon-geospatial", "nv5", "merrick", "red-wire-space",
    "iabg", "l3harris",
}

VALID = {"commercial-eo", "consultancy", "reseller", "software",
         "conglomerate", "nonprofit", "not-eo"}


def load_verdicts() -> dict:
    out = {}
    for f in sorted(glob.glob(str(db.DB / "_inbox" / "class_*.json"))):
        for r in json.load(open(f)):
            t = r.get("type")
            if t in VALID:
                out[r["slug"]] = (t, r.get("reason", ""))
    return out


def main() -> None:
    verdicts = load_verdicts()
    counts, changed = Counter(), []
    listed = 0
    excluded = {}
    for p in sorted(db.DB.glob("*.md")):
        rec = db.parse(p.read_text())
        slug = p.stem
        old = rec.get("type")

        if slug in CONGLOMERATES:
            typ, reason = "conglomerate", "known large multi-division company"
        elif slug in verdicts:
            typ, reason = verdicts[slug][0], verdicts[slug][1] + " [agent]"
        else:
            typ, reason = old or "commercial-eo", rec.get("type_reason", "unclassified")

        rec["type"], rec["type_reason"] = typ, reason
        is_listed = (typ == "commercial-eo" and rec["status"] == "active"
                     and bool(rec["careers_urls"]))
        rec["listed"] = is_listed
        counts[typ] += 1
        if is_listed:
            listed += 1
        elif typ != "commercial-eo":
            excluded.setdefault(typ, []).append(rec["name"])
        if old and old != typ:
            changed.append((rec["name"], old, typ))
        db.save(slug, rec)

    print("type distribution:", dict(counts))
    print("LISTED (commercial-eo + active + has careers):", listed)
    print(f"\ntype changed vs previous: {len(changed)}")
    for name, o, n in sorted(changed):
        print(f"  {name}: {o} -> {n}")


if __name__ == "__main__":
    main()
