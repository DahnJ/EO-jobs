---
name: discover-eo-companies
description: Use when finding and adding NEW Earth Observation companies to the EO-jobs directory — sweeps pre-filtered discovery sources (EO/space job boards, funding & space-news feeds), dedups candidates against the existing database, then verifies and classifies each genuinely-new company and updates the database + README. Triggers on requests like "find new EO companies", "discover companies we're missing", "run a discovery sweep", "add recently-funded geospatial startups", or "who's hiring in EO that we don't have yet". For re-checking companies already in the directory, use the refresh-eo-jobs skill instead.
---

# Discover EO companies (new additions)

Finds EO companies not yet in the directory and adds them. To re-verify existing
entries, use the sibling **refresh-eo-jobs** skill.

**Read `../_shared/pipeline.md` first** — architecture, cost discipline, subagent
failure modes, and the merge→classify→finish→handoff step are shared there. The
per-company field rules live in **`../_shared/company-contract.md`**; this file only
covers how a *discovery* run sources and dedups candidates before feeding them in.

## Source strategy (learned)

The DB now has broad coverage, so **static rosters are saturated** (a 2026-06 sweep
found 52% of candidates already present) and **broad WebSearch is low-SNR** (~36%
useful — lots of comms/IoT/agtech noise). Discovery's job is now *incremental*:
monitor **pre-filtered feeds that refresh over time** and diff new names against the
DB. Don't re-scrape static corpora every run.

## Steps

1. **Sweep recurring, pre-filtered feeds** (subagents in parallel, each returning a
   terse `Name|website` list):
   - **EO/space job boards** — the ones in README's "Portals & Jobs" section: Space
     Talent (`jobs.spacetalent.org`), Payload Jobs, Careers in Space, SpaceCareers.uk,
     ai-jobs.net, Climatebase. A company posting here is active and hiring — this is
     the highest-leverage source (and doubles as the freshness signal for refresh).
   - **Funding / news feeds** — TerraWatch Space, Payload, SpaceNews, the Seraphim
     Space index/quarterly reports, Space Capital. Pull recently-announced EO/space
     companies and funding rounds.
   - *Occasional gap-fill only* (saturated — skip most runs): GitHub
     `chrieke/awesome-geospatial-companies`, the Google Sheet categories, or a
     targeted WebSearch for one specific under-covered region.

2. **B1 dedup.** Concatenate candidates, then drop any whose slug or website domain
   already exists in the DB, plus any matching a known alias in
   `known_duplicates.json` (`just dedup-index` builds the comparison index). Only the
   genuinely-new remainder gets verified — this is the main cost saver.

3. **Verify (Haiku, parallel).** Split the new candidates into batches of ~18;
   dispatch Haiku subagents with `../_shared/company-contract.md` (discover mode — no
   priors, derive the slug). Each WebFetches its batch and writes
   `companies/_inbox/disc_N.json`, returning one status line. Verify each agent wrote
   one record per input line; re-run any shortfall.

4. **Merge + classify + finish.** `just merge "discovery-sweep YYYY-MM"`, then
   classify the new slugs (`just class-input` → Haiku agents per
   `../_shared/classify-prompt.md` → `companies/_inbox/class_N.json`), then
   `just readme`. Sanity-check + commit per `../_shared/pipeline.md`. If asked for a
   PR, flag additions as `[NEW]`.

## Scaling notes

- A 73-company discovery verification ran ~100k tokens total in Haiku batches.
- Classification is cheap (no fetch — reads stored descriptions): the whole DB fits
  in ~3 Haiku batches of ~175; usually you only classify the new slugs.
