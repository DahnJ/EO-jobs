---
name: refresh-eo-jobs
description: Use when re-verifying existing entries in the EO-jobs company directory — checks each company's links, locations, status, and remote-work policy against their live sites/careers pages and updates the database + README. For finding NEW companies, use the discover-eo-companies skill instead. Run on demand.
---

# Refresh EO-jobs (existing companies)

Re-verifies companies already in the directory. To add new ones, use the sibling
**discover-eo-companies** skill — both share the same database, helpers, and
finish step.

**Architecture.** The per-company database `companies/<slug>.md` is the source of
truth (full coverage, including acquired/defunct/non-EO). `README.md` is a
*generated, curated view* — only `listed == True` rows (commercial-EO + active +
has careers). Never hand-edit the README.

**Pipeline = `just` + `uv`.** Deterministic steps are `just` recipes (see the
`justfile`); they run via `uv` (stdlib-only, no deps to install). Agents do
judgment; recipes do mechanics. `just --list` shows them all.

Design rationale: `docs/superpowers/specs/2026-06-14-eo-jobs-refresh-agent-design.md`.

## Conventions

- **Conservative edits.** Change a field only when the live page clearly
  contradicts the current value. When unsure, leave it and note "could not verify".
- **Evidence for every `remote` change** (`remote_evidence`) — a short quote/
  observation. This is the column users care about most.
- **`remote` format:** `Yes` / `Hybrid` / `No`, optionally with a region —
  `Yes (US)`, `Yes (US/UK)`. Keep it consistent; `fixup_data.py` normalizes drift.
- **Never hand-edit the README.** Regenerate with `just readme`.

## Cost discipline

- **A1** — verification subagents return a one-line status, never the data.
- **A2** — agents write results as JSON to `companies/_inbox/<batch>.json`.
- **A3** — use `model: haiku` for verification.

## Steps

1. **Pick the batch.** Refresh the stalest entries (oldest `last_checked`) or a
   slice — not all ~530 every run. `just check` (link-rot sweep) finds companies
   with dead sites/careers links — **these are top priority, because a dead careers
   link is never an acceptable end state.** The per-company prompt requires
   re-resolving a 404 careers URL (footer link → search for the ATS → LinkedIn jobs
   page) rather than flagging it; a non-empty `careers_urls` that 404s is a bug, not
   a valid listing. The **EO job boards** (see discover-eo-companies) are the other
   freshness signal: a company currently posting there is active + hiring, so
   prioritize confirming those. Split the chosen slugs into groups of ~18.

2. **Verify (Haiku, parallel).** Dispatch one Haiku subagent per group (Agent tool,
   `model: haiku`, multiple calls per message) using `references/company-prompt.md`.
   Give each the company's CURRENT stored values so it only overrides on a clear
   contradiction. Each WebFetches its companies and **writes a JSON array to
   `companies/_inbox/refresh_N.json`**, returning only a one-line status.

3. **Browser fallback (optional, interactive).** Hosted ATS boards (BambooHR,
   Lever, Greenhouse, Workday) often 403 to WebFetch — where per-role remote tags
   live. If a batch reports many 403s **and** the run is interactive (user can
   approve per-domain prompts), load the Chrome tools (one `ToolSearch` call) and
   re-fetch those URLs **one at a time**. **Skip entirely when the user is remote /
   can't click approvals** — leave those rows with a "could not verify" note.
   Two things observed in practice: (a) **stored ATS URLs go stale constantly** — a
   404 usually means the company switched ATS, so re-resolve via the site's own
   Careers link rather than concluding it's dead; (b) **`get_page_text` returns
   nothing on BambooHR/Workday** (JS-rendered) — use `read_page` or a screenshot;
   (c) the board's "Remote" chip is not enough — open the posting for the geographic
   eligibility ("Remote — US/EU only" → `Yes (US/EU)`).

4. **Merge:** `just merge` (existing slugs are updated in place; `last_checked`
   restamped, `note` appended to the body).

5. **Finish:** `just readme` (recomputes `listed`, rebuilds the README). If a
   refresh changed a company's fundamental nature (e.g. it pivoted away from EO),
   re-classify it — see the classification step in **discover-eo-companies**.

6. **Sanity-check & commit:** `git diff --stat README.md` should be row-local; a
   full-table reflow means something regressed — stop and investigate. Then
   `rm -rf companies/_inbox` and commit the DB files + README together.

7. **Hand off.** **Do not open a PR unless explicitly asked** (repo owner's standing
   rule). Push the branch and hand over the compare/PR-create link. If asked for a
   PR, keep the body to `references/pr-template.md`, nothing else.

## Scaling notes

- Verification parallelizes well in Haiku batches of ~18.
- The browser fallback is the only interactive bottleneck — treat it as opt-in.
- Refresh a slice per run to keep diffs reviewable.
