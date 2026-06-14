# Shared pipeline (refresh + discover)

Both skills share one database, one set of `just` recipes, and one finish/handoff
step. Read this once; each skill's SKILL.md only adds the part that's unique to it.

## Architecture

- **The DB is the source of truth.** `companies/<slug>.md` is a per-company record
  (JSON-valued YAML frontmatter + free-text body), full coverage — including
  acquired/defunct/non-EO companies we deliberately keep but don't list.
- **`README.md` is a generated, curated view** — never hand-edit it. `just readme`
  renders only `listed == True` rows (commercial-EO + active + a real careers URL).
- **The README hides non-positive remote.** Only `Yes`/`Hybrid` show in the Remote
  column; `""`, `No`, and `No jobs` render blank. So a confirmed `No` enriches the
  DB but never changes the table — spend verification effort on confirming the
  *region* of a Yes/Hybrid, not on proving a No.
- **`just` + `uv` are the deterministic spine.** Agents do judgment; recipes do
  mechanics. `just --list` shows them. They run via `uv` (stdlib-only, no installs).

## Cost discipline

- **A1** — subagents return a one-line status, never the data.
- **A2** — agents write results as JSON to `companies/_inbox/<batch>.json`.
- **A3** — use `model: haiku` for verification and classification.
- **B1** (discover) — dedup candidates against the DB *before* spending fetches.

## Dispatching subagents — the two failure modes

1. **Under-delivery.** An agent's status line sometimes claims more records than it
   actually wrote (e.g. "177 verified" when the file has 128). **Verify each agent
   wrote one record per input line** and re-run any shortfall before merging.
2. **Rate-limiting.** Firing too many WebFetch agents at once makes whole batches
   come back all-`unknown`/all-`low` (the tell-tale signature). **Cap each wave at
   ~10–12 agents**; if a wave comes back uniformly empty, re-run it smaller.

## Merge → classify → finish

1. **Merge:** `just merge "<source> YYYY-MM"` applies every `companies/_inbox/*.json`.
   It creates new files (tagging their source) and updates existing ones in place,
   restamping `last_checked` and appending notes to the body. Guards you can rely on:
   it won't downgrade a known status to `unknown`, won't let a lower
   `remote_confidence` overwrite a higher one, and unions `links` without clobbering.
   - **Only merge positive findings you trust.** A subagent that returns `remote: ""`
     with `low` confidence after a failed fetch should *not* overwrite a good stored
     value — filter those out (or rely on the confidence guard) so a blocked fetch
     never erases real data.
2. **Classify** (mainly discover; also when a refresh finds a company pivoted): new
   companies need a `type`. Build input with `just class-input`, dispatch Haiku
   agents per `_shared/classify-prompt.md` (BROAD EO scope is the owner's standing
   decision), each writing `companies/_inbox/class_N.json`. `just readme` applies it.
3. **Finish:** `just readme` (recomputes `listed`, rebuilds the README). Then
   `git diff --stat README.md` should be **row-local** — a full-table reflow means
   something regressed; stop and investigate. `rm -rf companies/_inbox` and commit
   the DB files + README together.

## Cheap no-LLM health checks (run before spending a verification pass)

- `just check` — link-rot sweep over website + careers URLs. Treats 403/416 as
  alive (bot-block / range-not-satisfiable ≠ dead); a hard 404 on a careers URL is a
  bug to re-resolve, a 404 on a *website* often means a stale path (try the root).
- `just redirects` — listed sites whose domain now redirects to a *different* domain:
  almost always an acquisition/rebrand to mark and de-list. Catches what bot-blocked
  WebFetch agents miss.

## Hand off

**Do not open a PR unless explicitly asked** (repo owner's standing rule). Push the
branch and hand over the compare/PR-create link. If asked for a PR, keep the body to
`_shared/pr-template.md` and nothing else.

## Feed lessons back

When a run surfaces a new failure mode or the owner corrects a call, update the
relevant shared file (usually `company-contract.md`) so it doesn't recur — this is a
standing repo rule (see root `CLAUDE.md`). Optimize the one shared file, not copies.
