# EO-jobs

A curated directory of Earth Observation companies and their careers pages,
published as the `README.md` table. The most valuable column is **Remote**.

## How it's built
- **`companies/<slug>.md`** is the database (full coverage, incl. acquired/defunct).
  **`README.md` is generated** from it (`listed == True` rows only) — never hand-edit it.
- **`just` recipes** (run via `uv`) are the deterministic spine: `just readme`,
  `just merge`, `just check` (link-rot), `just redirects` (acquisitions). Agents do
  judgment; recipes do mechanics.
- **Two skills** drive the work: **refresh-eo-jobs** (re-verify existing entries)
  and **discover-eo-companies** (find + add new). Each `SKILL.md` is a thin
  orchestrator; the shared substance lives in `.claude/skills/_shared/` — chiefly
  `company-contract.md`, the canonical per-company field rules (Remote, careers
  re-resolution, acquisition detection).

## Standing rule
Feed lessons back: when the user corrects something or a run surfaces a failure
mode, fix it in the skill (usually `_shared/company-contract.md`), not just the one
instance — otherwise it recurs.
