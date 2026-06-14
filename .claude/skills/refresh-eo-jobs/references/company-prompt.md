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
- "careers_url": careers/jobs page URL, else "". Look for it — a footer "Careers"/
  "Jobs" link, a `/careers` path, or an ATS board (Lever/Greenhouse/Ashby/Workable).
  This field decides whether the company appears in the public README, so try.
- "links": object with any of these you can find (omit keys you can't): "linkedin",
  "crunchbase", "twitter", "github", "youtube". Check the homepage footer/header.
- "locations": array, HQ + major offices (e.g. ["San Francisco, US"]). [] if unknown.
- "remote": "Yes" | "Hybrid" | "No" | "", optionally with a region — "Yes (US)".
  Read between the lines from job listings / careers-page language.
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
