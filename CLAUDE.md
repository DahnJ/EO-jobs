# EO-jobs — working rules

## Always feed lessons back into the skill
When the user gives feedback, corrects a mistake, or a lesson emerges from a run,
capture it durably in the relevant skill — don't just fix the one instance. A
one-off fix that isn't reflected in the skill will recur. After resolving any issue,
ask: "what change to the skill would have prevented this?" and make it.

The crucial, most-corrected content — the per-company field rules (Remote, careers
re-resolution, acquisition detection) — lives in ONE canonical file,
`.claude/skills/_shared/company-contract.md`. Most lessons belong there. Edit that
single file, not per-skill copies (there are none any more — that's the point).

## Architecture (orientation)
- `companies/<slug>.md` is the database (full coverage). `README.md` is a generated,
  curated view (`listed == True` only). Never hand-edit the README.
- Deterministic steps are `just` recipes (`just readme`, `just merge`, `just check`,
  …), run via `uv`. Agents do judgment; recipes do mechanics.
- Two skills: **refresh-eo-jobs** (re-verify existing) and **discover-eo-companies**
  (find + add new). Each `SKILL.md` is a thin orchestrator; the shared substance is
  in `.claude/skills/_shared/` — `company-contract.md` (per-company field rules),
  `pipeline.md` (architecture + mechanics + gotchas), `classify-prompt.md`,
  `pr-template.md`.
