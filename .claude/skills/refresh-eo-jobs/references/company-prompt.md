# Refresh verification subagent prompt

Dispatch one **Haiku** subagent per batch of ~18 existing companies (Agent tool,
`model: haiku`). Provide each company's CURRENT stored values so the agent only
overrides a field on a clear contradiction. The output keys match what
`merge_inbox.py` (via `just merge`) consumes.

---

You are re-verifying existing Earth Observation company entries. For EACH company
below, use WebFetch on its website (and careers page) to check the stored values.
Be conservative — only change a field when the live page clearly contradicts it.
At most 1-2 WebFetch calls per company; if a site fails after 1 retry, keep the
stored value and note "could not verify".

For each company produce a JSON object with these exact keys:

- "slug": the slug given (do not change it).
- "name": the company name.
- "status": "active" | "acquired" | "defunct" | "renamed" | "unknown".
- "website": canonical homepage (https). If it redirects, use the new URL.
- "careers_url": careers/jobs page URL, else "". **You MUST verify it resolves and
  re-resolve a dead one — never leave or report a 404.** ATS boards go stale
  constantly: a 404 almost always means the company switched ATS
  (Lever↔Greenhouse↔Ashby↔JazzHR↔BambooHR↔Workable↔Personio), not that they stopped
  hiring. If the stored URL 404s, work this ladder until something resolves:
  (1) the site's own "Careers"/"Jobs" footer/header link (don't give up if
  `/careers` 404s — try the homepage); (2) search "<name> careers" / "<name>
  greenhouse|lever|ashby"; (3) the company's LinkedIn jobs page
  (`linkedin.com/company/<slug>/jobs/` — loads without login). Use the first
  working page as careers_url. Only if EVERY option fails — including LinkedIn
  showing "no jobs right now" — record that in `note` ("no current openings") and
  set careers_url to the working LinkedIn jobs page anyway (a valid pointer beats a
  404). This field decides README inclusion.
- "links": object with any of these you can find (omit keys you can't): "linkedin",
  "crunchbase", "twitter", "github", "youtube". Check the homepage footer/header.
- "locations": array, HQ + major offices (e.g. ["San Francisco, US"]). [] if unknown.
- "remote": "Yes" | "Hybrid" | "No" | "", optionally with a region — "Yes (US)",
  "Yes (US/EU)", "Yes (Europe)". **Read an ACTUAL job posting, not the board's
  summary chip.** A role shown as "Remote" on the board listing usually restricts
  eligibility to a region in the posting body (e.g. "Remote — US or EU only") — open
  a representative posting and capture that geography. Bare "Yes" is rarely correct.
  **Export-control / work-authorization language scopes remoteness:** a "remote"
  role that mentions ITAR/EAR, "US export control", "must be a US person", or "US
  work authorization required" is effectively "Yes (US)"; the equivalent for other
  countries applies too.
- "remote_evidence": one short sentence with the evidence (quote/observation). "".
- "description": one sentence (≤ ~25 words) on what the company does.
- "note": "" normally; flag acquired/defunct/renamed, a dead careers link, or if
  the company has clearly pivoted away from EO.

CURRENT DATA (one block per company):
<slug / name / website / careers_url / locations / remote — as stored>

OUTPUT INSTRUCTIONS (important for cost):
- Write the JSON array to companies/_inbox/refresh_N.json (use your batch number).
- Do NOT print the JSON back. Final message = ONLY one line, e.g.
  "refresh_2: 18 verified, 2 status changes, 1 remote change".
