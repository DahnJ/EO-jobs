---
name: refresh-eo-jobs
description: Use when refreshing or updating the EO-jobs company directory — re-verifies each company's links, locations, and remote-work policy against their live sites/careers pages, discovers new Earth Observation companies, and opens a PR with the changes. Run on demand.
---

# Refresh EO-jobs

Automates upkeep of the Earth Observation company directory. The CSV
`earth-observation-jobs - Companies.csv` is the source of truth (plain LF, so
ordinary pandas edits give clean diffs); `generate_readme.py` renders it into
`README.md`. A run re-verifies existing companies, discovers new ones, and opens
**one PR for review**.

Design rationale and the validated fetch strategy live in
`docs/superpowers/specs/2026-06-14-eo-jobs-refresh-agent-design.md`.

## Core conventions

- **Conservative edits.** Only change a field when the page clearly contradicts
  the current value. When unsure, leave it and note "could not verify".
- **Evidence for every `Remote` change.** Record a short quote/observation and
  which page it came from. This is the column users care about most.
- **Regenerate, don't hand-edit, the README.** After editing the CSV, run
  `generate_readme.py`. Never edit the table in `README.md` directly.

## Setup

1. Per the repo's worktree rule, work on a branch off `master` in a worktree
   (e.g. `refresh/YYYY-MM-DD`).
2. Ensure the venv exists with deps:
   `python3 -m venv .venv && .venv/bin/pip install -q pandas tabulate`
   Use `.venv/bin/python` for the script runs below.

## Stage 1 — Refresh existing companies (parallel WebFetch)

1. Read the CSV columns `Name, Description, Satellites, Website, Jobs site,
   Jobs 2, Locations, Remote` for all rows.
2. Fan out **subagents in parallel, ~10 concurrent** (Agent tool, multiple
   calls per message), one per company, using the prompt template in
   `references/company-prompt.md`. Each returns a structured report
   (link health, field suggestions, and `Remote` with evidence + confidence).
3. Collect the reports. Track every company whose Website / Jobs site / ATS URL
   returned **HTTP 403 or an empty body** — these go to Stage 1.5.

## Stage 1.5 — Browser fallback (sequential)

Hosted ATS boards (BambooHR, Lever, Greenhouse, Darwinbox, …) routinely return
403 to WebFetch, and that is exactly where per-role remote tags live. For each
company flagged in Stage 1:

1. Load the Chrome browser tools (one `ToolSearch` call — see the MCP guidance
   in the system prompt). There is one shared Chrome instance, so process these
   **one at a time**.
2. `navigate` to the blocked URL, then `get_page_text`.
   - Real content → re-derive the company's findings (especially `Remote`),
     raising confidence.
   - 404 / "not found" → the URL is genuinely **dead**, not blocked; propose a
     replacement (the company's own embedded careers board) or flag it.
3. Only after both passes fail is a page declared truly unreadable; leave that
   row unchanged with a "could not verify" note.

## Stage 2 — Discover new companies

Sweep these sources for EO companies **not already in the CSV** (match on Name +
Website, case-insensitive; when unsure if it's a duplicate, skip):

- GitHub `chrieke/awesome-geospatial-companies`.
- Google Sheet (fetch the CSV export form, not the editor URL):
  `https://docs.google.com/spreadsheets/d/1YieNiDHVTC5CfX13n72fXuceDaubSuyrghgAnxipsbY/export?format=csv&gid=0`
- The geospatial / climate job newsletters cited in `README.md`.

For each genuinely new EO company, gather what can be verified (at minimum Name,
Website, Description, Locations) and add it as a new row. Flag every addition as
`[NEW]` in the PR body — these need extra scrutiny.

## Stage 3 — Apply, regenerate, open PR

Apply all collected changes to the CSV with a few lines of pandas, then
regenerate. New companies are just Names not yet present:

```python
import pandas as pd
f = "earth-observation-jobs - Companies.csv"
df = pd.read_csv(f, dtype=str, keep_default_na=False).set_index("Name")
for name, fields in CHANGES.items():       # {"Company": {"Column": "value"}}
    for col, val in fields.items():
        df.loc[name, col] = val            # a new Name creates a new row
df.reset_index().to_csv(f, index=False)    # LF in, LF out — diffs stay row-local
```

(Use the internal `Notes` column for provenance like acquisitions — it is not
rendered in the README.)

Then:

1. `.venv/bin/python generate_readme.py`
2. Sanity-check: `git diff --stat` — both diffs should be **row-local** (only
   changed companies). A full-table reflow means something regressed; stop and
   investigate.
3. Commit (CSV + README together), push the branch.
4. Open one PR. Body = the changelog template in `references/pr-template.md`,
   nothing else. The **Remote changes** section (with evidence) is what the
   reviewer checks closely.

Note: opening the PR is the final step; if PR creation is gated, push the branch
and hand over the PR-create link.

## Scaling notes

- Stage 1 parallelizes well (185 companies in batches of ~10). Stage 1.5 is the
  sequential bottleneck — expect ~30–50 companies to need the browser.
- To keep PRs reviewable at full scale, running a slice per PR (e.g. the
  companies most likely stale) is fine rather than all 185 at once.
