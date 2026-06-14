---
name: refresh-eo-jobs
description: Use when re-verifying or correcting entries ALREADY in the EO-jobs company directory — re-checks each company's careers link, locations, status (active/acquired/defunct), and remote-work policy against their live sites and job postings, then updates the per-company database and regenerates the README. Triggers on requests like "refresh the EO jobs list", "re-check the remote statuses", "find dead careers links", "did company X get acquired", "the data is stale", or any spot-check/correction of existing companies. For finding and adding NEW companies, use the discover-eo-companies skill instead.
---

# Refresh EO-jobs (existing companies)

Re-verifies companies already in the directory and fixes what's drifted. To add new
ones, use the sibling **discover-eo-companies** skill.

**Read `../_shared/pipeline.md` first** — it covers the architecture (DB is truth,
README is generated and hides non-positive remote), cost discipline, the
subagent failure modes, and the merge→finish→handoff step that this skill shares.

The judgment that matters lives in **`../_shared/company-contract.md`** — the
per-company field rules (especially the Remote column, careers re-resolution, and
acquisition detection). That contract is the crucial, optimizable core; this file is
just how a *refresh* run feeds existing companies through it.

## Steps

1. **Pick the batch — target what's most likely wrong.** Don't re-check all ~530
   every run. Three signals point you at what needs attention:
   - `just check` (link-rot) — dead site/careers links. A careers 404 is a bug to
     re-resolve (see the contract's careers ladder), not a valid listing.
   - `just redirects` — listed companies whose domain now redirects elsewhere:
     almost always an acquisition/rebrand to mark `acquired`/`renamed` and de-list.
   - **EO job boards** (see discover-eo-companies for the list) — a company posting
     there right now is active + hiring, so its row is worth confirming.
   Otherwise, refresh the stalest entries (oldest `last_checked`). Split the chosen
   slugs into groups of ~16–18; cap each dispatch wave at ~10–12 agents.

2. **Verify (Haiku, parallel).** One Haiku subagent per group (Agent tool,
   `model: haiku`), each given `../_shared/company-contract.md` **plus the current
   stored values** for its companies (refresh mode — override only on a clear
   contradiction). Each WebFetches its companies and writes
   `companies/_inbox/refresh_N.json`, returning one status line. Verify each agent
   wrote one record per input line before trusting it.

3. **Browser fallback (optional, interactive).** Hosted ATS boards (BambooHR, Lever,
   Greenhouse, Workday, Recruitee) often 403 to WebFetch — and that's exactly where
   per-role remote geography lives, so these are the rows that stay `low` confidence.
   If a batch reports many 403s **and** the user can approve per-domain prompts, load
   the Chrome tools (one `ToolSearch` call) and re-fetch those URLs **one at a time**.
   Notes from practice: `get_page_text` returns nothing on BambooHR/Workday (JS-
   rendered — use `read_page` or a screenshot); a stale ATS URL means re-resolve via
   the site's own Careers link, not "dead"; open the actual posting for geography,
   not the board's "Remote" chip. **Skip entirely when the user can't click
   approvals** — leave those rows `low` with a "could not verify" note.

4. **Merge + finish:** `just merge "refresh YYYY-MM"`, then `just readme`. If a
   refresh reveals a company pivoted away from EO, re-classify it (see the classify
   step in discover-eo-companies). Sanity-check + commit per `../_shared/pipeline.md`.
