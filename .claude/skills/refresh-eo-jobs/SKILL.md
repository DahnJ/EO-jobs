---
name: refresh-eo-jobs
description: Use when refreshing or updating the EO-jobs company directory — re-verifies each company's links, locations, and remote-work policy against their live sites/careers pages, discovers new Earth Observation companies, and regenerates the README. Run on demand.
---

# Refresh EO-jobs

Automates upkeep of the Earth Observation company directory.

**Architecture.** The per-company database `companies/<slug>.md` is the source of
truth — full coverage, including acquired/defunct/non-EO companies. The public
`README.md` is a *generated, curated view*: only companies with `listed == True`
(commercial-EO + active + has a careers page) appear in the table. Never hand-edit
the README table.

```
companies/*.md  ──classify.py──▶  type + listed
       │                                │
   (db.py loader)              generate_readme.py
       │                                │
       └────────────────────────────────▶  README.md  (listed only)
```

Design rationale and the validated fetch strategy live in
`docs/superpowers/specs/2026-06-14-eo-jobs-refresh-agent-design.md`.

## Core conventions

- **Conservative edits.** Only change a field when the page clearly contradicts
  the current value. When unsure, leave it and note "could not verify".
- **Evidence for every `remote` change.** Record a short quote/observation in
  `remote_evidence`. This is the column users care about most.
- **Regenerate, don't hand-edit, the README.** Run `generate_readme.py` after any
  DB change. Verify `git diff --stat README.md` stays row-local.
- **The DB record schema** (JSON-valued YAML frontmatter, parseable without a YAML
  lib) is defined by `db.py`'s `FIELD_ORDER`. See any `companies/*.md` for the shape.

## Cost discipline (this skill is token-heavy at scale — keep it cheap)

These four rules are baked into the stages below; follow them, don't re-derive them:

- **A1 — terse agent returns.** Verification subagents return a single status line,
  never the per-company data. The orchestrator never re-transcribes records.
- **A2 — agents write to files.** Each subagent writes its results as a JSON array
  directly to `companies/_inbox/<batch>.json`. No data flows back through chat.
- **A3 — Haiku for verification.** Dispatch verification/triage subagents with
  `model: haiku`. Reserve larger models for genuine judgment calls.
- **B1 — dedup before verifying.** Match discovery candidates against the existing
  DB (by slug + website domain) and drop known ones *before* spending fetches.

## Setup

1. Per the repo's worktree rule, work on a branch off `master` in a worktree
   (e.g. `refresh/YYYY-MM-DD`).
2. Ensure the venv exists with deps: `python3 -m venv .venv && .venv/bin/pip install -q pandas`
   Use `.venv/bin/python` for all script runs. (`db.py`/`classify.py`/`merge_inbox.py`
   need no third-party deps; only legacy tooling used pandas.)
3. `mkdir -p companies/_inbox` (scratch space; delete it before committing).

## Stage 1 — Refresh existing companies

Refresh the entries most likely to be stale (oldest `last_checked`, or a slice).
Don't blindly re-verify all ~530 every run.

1. Pick the batch of slugs to refresh. Split into groups of ~18.
2. Fan out **Haiku subagents in parallel** (Agent tool, `model: haiku`, multiple
   calls per message), one per batch, using the prompt in
   `references/company-prompt.md`. Each agent WebFetches its companies and **writes
   a JSON array to `companies/_inbox/refresh_N.json`** (A2), returning only a
   one-line status (A1).
3. Apply: `.venv/bin/python merge_inbox.py` (existing slugs are updated in place;
   `last_checked` is restamped, `note` appended to the body).

### Browser fallback (optional, sequential, interactive)

Hosted ATS boards (BambooHR, Lever, Greenhouse, Workday, …) often return 403 to
WebFetch — and that is exactly where per-role remote tags live. If a batch reports
many 403s and the run is interactive (the user can approve per-domain prompts),
load the Chrome tools (one `ToolSearch` call) and re-fetch those URLs **one at a
time** with `navigate` + `get_page_text`. **Skip this entirely when the user is
remote / can't click approvals** — leave those rows with a "could not verify" note.

## Stage 2 — Discover new companies

1. **Sweep sources** for EO companies. Use several lenses (subagents can run these
   in parallel, each returning a terse `Name|website` list):
   - GitHub `chrieke/awesome-geospatial-companies` (the 🛰️ EO-focus marker).
   - Google Sheet CSV export (not the editor URL), across its categories — Earth
     Observation, Satellite Operator, Digital Farming, UAV/Aerial, GIS/Spatial:
     `https://docs.google.com/spreadsheets/d/1YieNiDHVTC5CfX13n72fXuceDaubSuyrghgAnxipsbY/export?format=csv&gid=0`
   - Multi-lens WebSearch (by application: maritime, methane/emissions, forestry/
     carbon, insurance/risk; by region; by recent funding).
2. **B1 dedup.** Concatenate candidates, then drop any whose slug or website domain
   already exists in the DB. Only the genuinely-new remainder gets verified.
3. **Verify (Haiku, A1+A2+A3).** Split the new candidates into batches of ~18 and
   dispatch Haiku subagents with the `references/company-prompt.md` discovery
   variant — each writes `companies/_inbox/disc_N.json`, returns one status line.
4. **Merge:** `.venv/bin/python merge_inbox.py --source "discovery-sweep YYYY-MM"`
   (creates new files; existing ones, if any slipped past dedup, are updated).

## Stage 3 — Classify, regenerate, hand off

**Classification is an agent judgment, not keyword matching.** The `type` taxonomy
(commercial-eo | consultancy | reseller | software | conglomerate | nonprofit |
not-eo) decides README inclusion, and the commercial-eo boundary is genuinely
fuzzy — so an agent reads each company's stored description and decides.

1. **Classify (agent, A2).** Generate a compact `{slug, name, desc, body}` JSONL of
   the companies to (re)classify — new ones at minimum, or all — split into batches
   of ~175. Dispatch Haiku subagents that read a batch and write
   `companies/_inbox/class_N.json` as `[{slug, type, reason}]`. **Use the BROAD
   definition** (repo owner's standing decision): a company is `commercial-eo` if it
   uses EO / satellite / aerial / remote-sensing data as a *core input* — including
   climate-risk, parametric insurance, carbon MRV, precision-ag, and emissions/
   methane monitoring built on EO. Reserve `not-eo` for genuinely unrelated
   businesses (farm-management software, KYC, supply-chain finance, generic AI).
   *Verify each agent wrote one record per input line* — they sometimes under-deliver
   and lie in the status line; re-run any shortfall.
2. `.venv/bin/python classify.py` — applies the agent verdicts from the inbox, plus a
   CONGLOMERATES safety net, and sets `listed = commercial-eo + active + has careers`.
   Prints what changed vs the previous types — review it. With no inbox files present
   it just recomputes `listed` from existing types (use after a hand-edit).
3. `.venv/bin/python generate_readme.py` — rebuilds the README from `listed` rows.
4. **Sanity-check:** `git diff --stat README.md` — changes should be row-local.
   A full-table reflow means something regressed; stop and investigate.
5. `rm -rf companies/_inbox`, then commit the DB files + README together. (Agent
   `type`/`reason` are persisted into each file, so the inbox is safe to delete.)
6. **Do not open a PR unless explicitly asked** (repo owner's standing rule). Push
   the branch and hand over the compare/PR-create link. If asked for a PR, keep the
   body to the changelog in `references/pr-template.md`, nothing else.

## Scaling notes

- Stage 1 and Stage 2 verification both parallelize well in Haiku batches of ~18;
  a 73-company discovery verification ran for ~100k tokens total.
- The browser fallback is the only sequential, interactive bottleneck — treat it as
  opt-in, not part of the default unattended run.
- To keep diffs reviewable, refresh a slice per run rather than the whole DB.
