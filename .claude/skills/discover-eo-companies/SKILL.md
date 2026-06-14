---
name: discover-eo-companies
description: Use when finding and adding NEW Earth Observation companies to the EO-jobs directory — sweeps discovery sources, dedups against the existing database, verifies and classifies each new company, and updates the database + README. For re-checking companies already in the directory, use the refresh-eo-jobs skill instead. Run on demand.
---

# Discover EO companies (new additions)

Finds EO companies not yet in the directory and adds them. To re-verify existing
entries, use the sibling **refresh-eo-jobs** skill — both share the same database,
helpers, and finish step.

**Architecture.** The per-company database `companies/<slug>.md` is the source of
truth (full coverage). `README.md` is a *generated, curated view* — only
`listed == True` rows (commercial-EO + active + has careers). Never hand-edit it.

**Pipeline = `just` + `uv`.** Deterministic steps are `just` recipes (see the
`justfile`), run via `uv` (stdlib-only). Agents do judgment; recipes do mechanics.

## Cost discipline

- **A1** — subagents return a one-line status, never the data.
- **A2** — agents write results as JSON to `companies/_inbox/<batch>.json`.
- **A3** — use `model: haiku` for verification and classification.
- **B1** — dedup candidates against the DB *before* spending fetches.

## Steps

> **Source strategy (learned).** The DB now has broad coverage, so static rosters
> are ~saturated (a 2026-06 sweep found 52% of candidates already present) and broad
> WebSearch is low-SNR (~36% useful, lots of comms/IoT/agtech noise). Discovery's job
> is now *incremental*: monitor **pre-filtered feeds that refresh over time** and diff
> new names against the DB. Don't re-scrape static corpora every run.

1. **Sweep recurring, pre-filtered feeds** (subagents in parallel, each returning a
   terse `Name|website` list):
   - **EO/space job boards** — the ones in README's "Portals & Jobs" section: Space
     Talent (`jobs.spacetalent.org`), Payload Jobs, Careers in Space, SpaceCareers.uk,
     ai-jobs.net, Climatebase. A company posting here is **active and hiring** — so
     this doubles as the freshness signal for `refresh-eo-jobs`. Highest-leverage
     source: pull the hiring companies, diff against the DB.
   - **Funding / news feeds** — TerraWatch Space, Payload, SpaceNews, the Seraphim
     Space index/quarterly reports, Space Capital. Pull recently-announced EO/space
     companies and funding rounds (real + new entrants).
   - *Occasional / gap-fill only* (saturated — don't run every time): GitHub
     `chrieke/awesome-geospatial-companies`, the Google Sheet categories, or a
     targeted WebSearch for one specific under-covered region.

2. **B1 dedup.** Concatenate candidates, then drop any whose slug or website domain
   already exists in the DB, plus any matching a known alias in
   `known_duplicates.json`. Only the genuinely-new remainder gets verified.

3. **Verify (Haiku, A1+A2+A3).** Split new candidates into batches of ~18; dispatch
   Haiku subagents with `references/company-prompt.md` — each WebFetches its batch
   and writes `companies/_inbox/disc_N.json`, returning one status line. *Verify
   each agent wrote one record per input line — they sometimes under-deliver and
   the status line lies; re-run any shortfall.*

4. **Merge:** `just merge "discovery-sweep YYYY-MM"` (creates new files; tags their
   source). Existing files that slipped past dedup are updated in place.

5. **Classify (agent, BROAD scope).** New companies need a `type`. Build the agent
   input with `just class-input`, split into batches of ~175, dispatch Haiku
   subagents using `references/classify-prompt.md`, each writing
   `companies/_inbox/class_N.json` as `[{slug, type, reason}]`. The **broad** EO
   definition is the repo owner's standing decision — see the prompt file. (You can
   classify only the new slugs rather than the whole DB.)

6. **Finish:** `just readme` (applies the classification verdicts + rebuilds the
   README). Review the "type changed" summary it prints. `git diff --stat README.md`
   should be row-local. Then `rm -rf companies/_inbox` and commit the DB + README.

7. **Hand off.** **Do not open a PR unless explicitly asked.** Push the branch and
   hand over the compare link. Flag new additions as `[NEW]` if asked for a PR
   (`references/pr-template.md`).

## Scaling notes

- A 73-company discovery verification ran ~100k tokens total in Haiku batches.
- Classification is cheap (no fetch — reads stored descriptions): the whole DB
  fits in ~3 Haiku batches of ~175.
