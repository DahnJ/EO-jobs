# Discovery verification subagent prompt

Dispatch one **Haiku** subagent per batch of ~18 new (post-dedup) candidates
(Agent tool, `model: haiku`). The output keys match what `merge_inbox.py` (via
`just merge`) consumes.

---

You are verifying newly-discovered Earth Observation company candidates. For EACH
company below, use WebFetch on its website (and careers page) to determine the
facts. At most 1-2 WebFetch calls per company; if a site fails after 1 retry,
record what you can and set status "unknown".

For each company produce a JSON object with these exact keys:

- "slug": lowercase the name, replace each run of non-alphanumeric chars with a
  single hyphen, strip leading/trailing hyphens ("Salo Sciences" → "salo-sciences").
- "name": the company name as given.
- "status": "active" | "acquired" | "defunct" | "renamed" | "unknown".
- "website": canonical homepage (https).
- "careers_url": careers/jobs page URL, else "". **Re-resolve it — ATS boards go
  stale.** A 404 almost always means the company switched ATS (Lever↔Greenhouse↔
  Ashby↔JazzHR↔BambooHR↔Workable↔Personio), not that they stopped hiring. Find the
  live one: follow the site's own "Careers"/"Jobs" footer/header link (don't give up
  if `/careers` 404s), or search "<name> careers". This decides README inclusion.
- "links": object with any of these you can find (omit keys you can't): "linkedin",
  "crunchbase", "twitter", "github", "youtube". Check the homepage footer/header.
- "locations": array, HQ + major offices. [] if unknown.
- "remote": "Yes" | "Hybrid" | "No" | "", optionally with a region — "Yes (US)",
  "Yes (US/EU)", "Yes (Europe)". **Read an ACTUAL job posting, not the board's
  summary chip.** A role shown as "Remote" on the listing index usually restricts
  eligibility to a region in the posting body (e.g. "Remote — US or EU only") — open
  a representative posting and capture that geography. Bare "Yes" is rarely correct.
- "remote_evidence": one short sentence with the evidence. "".
- "description": one sentence (≤ ~25 words) on what the company does, noting
  whether it is an Earth Observation / satellite / geospatial company.
- "note": "" normally; flag if NOT earth-observation (write "not an EO company"),
  acquired/defunct, or a likely duplicate of a known company. For a candidate with
  no URL, or that a quick search can't confirm exists, set status "unknown" and say
  so here so the orchestrator can drop it.

OUTPUT INSTRUCTIONS (important for cost):
- Write the JSON array to companies/_inbox/disc_N.json (use your batch number).
- Do NOT print the JSON back. Final message = ONLY one line, e.g.
  "disc_2: 18 companies written, 13 active, 3 unknown".

Companies to verify:
<Name|website, one per line>
