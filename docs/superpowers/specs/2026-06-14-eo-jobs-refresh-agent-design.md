# EO-jobs Refresh Agent — Design

**Date:** 2026-06-14
**Status:** Approved (pending spec review)

## Problem

The EO-jobs repo curates ~185 Earth Observation companies and links to their
job pages. It is maintained by hand: edit a Google Sheet → run a Jupyter
notebook → commit the regenerated `README.md`. The list has not had a real
update since July 2024 and is now stale. The most valuable and most fragile
column — **Remote** — requires reading between the lines of careers pages, which
is exactly the kind of judgment an agent can do at scale.

## Goal

Replace the manual loop with an **on-demand local agent** that refreshes the
directory and proposes new companies, then opens a **PR for human review**. Keep
the existing format and functionality — this is automation of the current
workflow, not a new product. No live per-role job listings; links to careers
pages remain the unit.

Approach **A (one-shot batch refresh)**: one invocation does the whole list and
opens one PR. PR-for-review now; a path to more autonomy later is noted but out
of scope for this build.

## Non-goals

- Live scraping of individual job postings.
- A website, database, or schema change to the published table.
- Scheduled/CI execution (this build is local/on-demand only).
- Auto-committing changes (every run produces a PR for review).

## Source of truth & prerequisite refactor

- The in-repo CSV **`earth-observation-jobs - Companies.csv`** becomes the
  source of truth, edited directly by the agent. The Google Sheets round-trip
  is dropped.
- **Delete** `process-eo-companies.ipynb` and replace it with
  **`generate_readme.py`** — same logic (load CSV, drop `na_values`
  `['?', 'None?', 'x']`, sort case-insensitively by `Name`, render the
  HTML-in-markdown table, prepend the static intro block, overwrite
  `README.md`), but runnable headlessly as `python generate_readme.py`.
  - The large static intro/header text currently embedded in the notebook moves
    into `generate_readme.py` (or a sibling `intro.md` the script reads).
  - Output must be byte-stable given unchanged input, so PR diffs reflect only
    real data changes.

## Architecture

A repo skill at **`.claude/skills/refresh-eo-jobs/`**, invoked on demand from
Claude Code. A single run executes these stages in order:

### Stage 1 — Refresh existing companies

- Load the CSV into rows.
- **Fan out subagents in parallel, batched (~10 concurrent)** — one per company.
  Each subagent, using the built-in **`WebFetch`** tool:
  - Fetches the company website and careers/jobs page(s).
  - Verifies `Website`, `Jobs site`, `Jobs 2` links resolve; flags dead or
    redirected URLs (and proposes the new URL when an obvious redirect target
    exists).
  - Updates **`Locations`**, **`Description`**, **`Satellites`** when the page
    clearly contradicts the current value. Conservative: only change on clear
    evidence, otherwise leave as-is.
  - Determines **`Remote`** by reading the careers page, and records a one-line
    **evidence string** for the call (quote or paraphrase + which page).
  - Returns a **structured record** (changed fields + the Remote evidence). Use
    the Agent/Workflow `schema` option so results come back validated, not as
    prose to parse.
- A subagent that cannot fetch a page (timeout, empty body) returns the row
  **unchanged** and notes "could not verify" rather than guessing.

#### Fetch strategy: WebFetch-first, browser-fallback

Validated against the sample: hosted ATS boards (BambooHR, Lever, Greenhouse,
Darwinbox) frequently return **HTTP 403** to WebFetch — and that is exactly
where per-role remote tags live, so it directly degrades the Remote column.

- **Pass 1 (parallel):** WebFetch subagents, ~10 concurrent. Handles the
  majority of companies and their own `/careers` pages.
- **Pass 2 (browser fallback, more sequential):** any company whose careers/ATS
  URL returned 403 or an empty body in pass 1 is retried through Chrome
  (`navigate` + `get_page_text`). There is one shared Chrome instance, so this
  pass is largely sequential — expect ~30–50 of 185 companies to need it.

The browser does two distinct jobs, both confirmed on the sample:
- Reads genuinely bot-blocked boards (Satellogic's BambooHR board loaded fully
  in Chrome after a WebFetch 403 → Remote went `low`/unverified → `high`).
- Disambiguates WebFetch 403s into "alive but blocked" vs "actually gone"
  (Albedo's Lever board returned a real 404 in Chrome → the jobs-site URL is
  dead, not blocked).

Only after both passes is a careers page declared truly unreadable and the row
left unchanged with a "could not verify" note.

### Stage 2 — Discover new companies

Sweep these sources for EO companies **not already in the CSV** (match on Name +
Website, case-insensitive):

- `chrieke/awesome-geospatial-companies` (GitHub).
- The geospatial / climate job newsletters already cited in the README.
- Google Sheet:
  `https://docs.google.com/spreadsheets/d/1YieNiDHVTC5CfX13n72fXuceDaubSuyrghgAnxipsbY/export?format=csv&gid=0`
  (the `export?format=csv` form is fetchable by WebFetch; the `/edit#gid=` URL
  is not).

For each genuinely new EO company, append a proposed row with as many fields
filled as can be verified (at minimum Name, Website, Description, Locations).
New rows are flagged `[NEW]` in the PR body so they get extra scrutiny.

### Stage 3 — Regenerate & open PR

- Write updated + appended rows back to the CSV.
- Run `python generate_readme.py` to regenerate `README.md`.
- Create a branch (e.g. `refresh/YYYY-MM-DD`) and open **one PR**.

## PR contents

The branch carries the CSV + README diff. The PR body is a concise changelog,
nothing more:

- **Links fixed** — dead/redirected URLs and their replacements.
- **Fields updated** — Location/Description/Satellites changes, one line each.
- **Remote changes** — a dedicated section, one line per change with evidence,
  e.g. `Albedo: Remote No→Yes ("all roles listed as remote-friendly", careers
  page, 2026-06)`. This is the section to review closely.
- **New companies** — each `[NEW]` row with its source and a one-line rationale.

The CSV schema is unchanged: evidence/reasoning lives only in the PR body, never
in the data.

## Error handling

- Unreachable pages → row left unchanged, listed under a "could not verify"
  note in the PR so coverage gaps are visible (no silent skips).
- Discovery dedup is conservative: when unsure whether a company is already
  listed, treat it as a duplicate and skip rather than create a near-duplicate
  row.
- A run that changes nothing opens no PR and says so.

## Future (out of scope, noted for design continuity)

- Tiered autonomy: auto-commit mechanical changes (dead links, README
  regeneration), keep judgment calls (Remote, new companies) as PRs.
- Scheduled execution via GitHub Actions cron once trust is established.
- A `last_checked` timestamp per row to enable sliced/incremental runs.

## Components summary

| Unit | Purpose | Depends on |
|------|---------|------------|
| `generate_readme.py` | CSV → README.md, headless, deterministic | CSV, pandas |
| `.claude/skills/refresh-eo-jobs/` | Orchestrates refresh + discovery + PR | WebFetch, Chrome browser tools (fallback), subagents, `generate_readme.py`, `gh` |
| CSV (in-repo) | Source of truth, edited by agent | — |
