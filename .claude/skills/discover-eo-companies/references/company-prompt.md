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
- "status": "active" | "acquired" | "defunct" | "renamed" | "unknown". **Follow
  redirects.** If the company's own domain redirects to a DIFFERENT company's site,
  that's an acquisition/merger — set "acquired"/"renamed" and name the acquirer in
  `note`. A site that won't load via WebFetch (bot-blocked) is NOT evidence it's
  active — say so and set "unknown" rather than silently keeping "active".
- "website": canonical homepage (https).
- "careers_url": careers/jobs page URL, else "". **Verify it resolves; re-resolve a
  dead one — never leave or report a 404.** ATS boards go stale: a 404 usually means
  the company switched ATS (Lever↔Greenhouse↔Ashby↔JazzHR↔BambooHR↔Workable↔Personio),
  not that they stopped hiring. Work this ladder until something resolves: (1) the
  site's own "Careers"/"Jobs" footer/header link (don't give up if `/careers` 404s);
  (2) search "<name> careers" / "<name> greenhouse|lever|ashby"; (3) the company's
  LinkedIn jobs page (`linkedin.com/company/<slug>/jobs/` — loads without login).
  Use the first working page. Only if all fail (incl. LinkedIn "no jobs right now")
  record "no current openings" in `note` and still set careers_url to the working
  LinkedIn jobs page (a valid pointer beats a 404). This decides README inclusion.
  **NEVER fabricate a URL.** Don't guess a LinkedIn slug from the name —
  `linkedin.com/company/<name>` is a 404 unless that slug exists. Only append `/jobs`
  to a LinkedIn company page you actually verified for the "linkedin" link. Every
  careers_url must be one you fetched and saw resolve; an invented link is worse than
  "" (it lists the company with a broken link). If you can't verify one, return "".
- "links": object with any of these you can find (omit keys you can't): "linkedin",
  "crunchbase", "twitter", "github", "youtube". Check the homepage footer/header.
- "locations": array, HQ + major offices. [] if unknown.
- "remote": "Yes" | "Hybrid" | "No" | "", optionally with a region — "Yes (US)",
  "Yes (US/EU)", "Yes (Europe)". **Read an ACTUAL job posting, not the board's
  summary chip.** A role shown as "Remote" on the listing index usually restricts
  eligibility to a region in the posting body (e.g. "Remote — US or EU only") — open
  a representative posting and capture that geography. Bare "Yes" is rarely correct.
  **Export-control / work-authorization language scopes remoteness:** a "remote"
  role mentioning ITAR/EAR, "US export control", "must be a US person", or "US work
  authorization required" is effectively "Yes (US)" (same idea for other countries).
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
