# EO-jobs — working rules

## Always feed lessons back into the skill
When the user gives feedback, corrects a mistake, or a lesson emerges from a run,
capture it durably in the relevant skill — don't just fix the one instance. The
skills (`.claude/skills/refresh-eo-jobs`, `.claude/skills/discover-eo-companies`)
and their reference prompts are the source of truth for how the work is done; a
one-off fix that isn't reflected there will recur. After resolving any issue, ask:
"what change to the skill/prompt would have prevented this?" and make it.

## Architecture (orientation)
- `companies/<slug>.md` is the database (full coverage). `README.md` is a generated,
  curated view (`listed == True` only). Never hand-edit the README.
- Deterministic steps are `just` recipes (`just readme`, `just merge`, `just check`,
  …), run via `uv`. Agents do judgment; recipes do mechanics.
- Two skills: **refresh-eo-jobs** (re-verify existing) and **discover-eo-companies**
  (find + add new). Both share the DB, helpers, and finish step.
