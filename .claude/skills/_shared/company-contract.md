# Per-company field contract (shared by refresh + discover)

This is the heart of both skills: the rules for turning a company into one DB
record. Both the **refresh** and **discover** skills dispatch Haiku subagents that
WebFetch a company and emit one JSON object per company following this contract.
Optimize this file — not copies in each skill — when a field rule needs to change.

The keys below match what `merge_inbox.py` (via `just merge`) consumes. Each rule
explains *why* it exists, because most of them encode a mistake we already made;
understanding the failure lets you handle cases the examples don't cover.

## Two modes (one contract)

- **Refresh** gives each agent the company's **CURRENT stored values**. Treat them
  as the prior: change a field only when the live page **clearly contradicts** it,
  and keep the slug you were given. When you can't reach the site, keep the stored
  value and say "could not verify" — don't blank it.
- **Discover** gives only `Name|website` (no priors). Fill every field fresh and
  derive the slug: lowercase the name, replace each run of non-alphanumeric chars
  with a single hyphen, strip leading/trailing hyphens ("Salo Sciences" →
  "salo-sciences").

Budget ~1–3 WebFetch calls per company. This is a Haiku batch job — be terse.

## Output: one JSON object per company

- **`slug`** — keep the given slug (refresh) or derive it (discover, rule above).
- **`name`** — the company name.
- **`status`** — `active` | `acquired` | `defunct` | `renamed` | `unknown`.
  - **Follow redirects.** If the company's own domain lands on a *different*
    company's site (pachama.com → carbon-direct.com), that's an acquisition/merger:
    set `acquired`/`renamed` and name the acquirer in `note`. *Why:* a bot-blocked
    WebFetch once silently kept Pachama "active" long after it was absorbed — a
    cross-domain redirect is the signal that catches what a failed fetch hides.
  - **A site you can't load is not evidence it's alive.** Bot-block, "security
    verification", timeout → set `unknown` and say so in `note`. Don't default to
    `active` just because you couldn't disprove it.
- **`website`** — canonical homepage (https); if it redirects, use the destination.
  - A stored URL with a **localized/deep path** (`/en/home/`, `/en/`) can 404 while
    the **root domain still resolves** — try the bare root before concluding a
    company is dead. *Why:* three "dead" homepages turned out to be live sites with
    a moved path.
- **`careers_url`** — the careers/jobs page, else `""`. **This field decides README
  inclusion**, so it has to be real.
  - **A 404 is never an acceptable end state — re-resolve it.** ATS boards churn
    constantly; a dead link almost always means the company switched ATS
    (Lever↔Greenhouse↔Ashby↔JazzHR↔BambooHR↔Workable↔Personio), not that hiring
    stopped. Work this ladder until something resolves:
    1. the site's own Careers/Jobs link (footer/header) — don't give up if
       `/careers` 404s; try the homepage and follow its link;
    2. search `"<name> careers"` / `"<name> greenhouse|lever|ashby"`;
    3. the company's LinkedIn jobs page (`linkedin.com/company/<slug>/jobs/` —
       loads without login).
    Use the first page that resolves. If everything fails (incl. LinkedIn showing
    "no jobs right now"), note "no current openings" and still point `careers_url`
    at the working LinkedIn jobs page — a valid pointer beats a 404.
  - **Never fabricate a URL.** Don't guess a LinkedIn slug from the name —
    `linkedin.com/company/<name>` is a 404 unless that exact slug exists. Only build
    a `/jobs` URL by appending `/jobs` to a LinkedIn company page you actually
    verified for the `linkedin` link. **Every `careers_url` you return must be one
    you fetched and saw resolve.** An invented or unchecked link is *worse* than
    `""`: it gets the company listed in the README with a broken link. If you can't
    verify one, return `""` and explain in `note`. *Why:* agents once guessed ~10
    LinkedIn slugs that all 404'd and silently listed those companies as broken.
- **`links`** — object with any of `linkedin`, `crunchbase`, `twitter`, `github`,
  `youtube` (omit keys you can't find). Check the homepage footer/header and the
  Crunchbase result. *Why:* the README's Social/Business columns come from here, and
  the standing expectation is that **almost every company has a LinkedIn + a
  Crunchbase at minimum** — if you found none, look again before giving up; truly
  having none is rare.
- **`locations`** — array of `"City, Country"` (HQ + major offices), `[]` if
  unknown. Plain text is fine — the merge step auto-prepends the flag emoji. But
  give a real country so it *can* be flagged; "Remote"/"Global" are allowed and map
  to 🌐. *Why:* every location in the README must carry a flag.
- **`remote`** — the single most valuable column. `Yes` | `Hybrid` | `No` | `""`,
  optionally with a region: `Yes (US)`, `Yes (US/EU)`, `Yes (Europe)`,
  `Yes (Australia)`. Determine it with this rule, in order:
  1. If the company/careers page **states** a remote policy, record it — but keep
     looking for something stronger.
  2. If there are **actual job postings**, open a representative one and read the
     geography from the **posting body**. The board's "Remote" chip is *not* enough:
     postings routinely restrict eligibility ("Remote — US only"). Bare `Yes` is
     rarely correct — add the region whenever a posting names one.
  3. If you find **no posting that mentions remote**, that is **not** evidence of
     `No`. Leave `remote` unchanged (refresh) or `""` (discover) and set confidence
     `low`. Don't assert `No` from mere absence.
  - **Export-control / work-authorization language scopes remoteness.** A "remote"
    role mentioning ITAR/EAR, "US export control", "must be a US person", or "US
    work authorization required" is effectively `Yes (US)` (analogously for other
    countries).
  - The README **hides** `No`/`""` (only positive remote surfaces), so don't agonize
    over proving `No` — your effort is best spent confirming the *region* of a Yes/
    Hybrid.
- **`remote_evidence`** — one short sentence/quote backing the `remote` value, else
  `""`. This is what lets a human trust (or overturn) the call.
- **`remote_confidence`** — how you know:
  - `high` — you opened an actual posting (or an explicit company remote policy) and
    saw the geography.
  - `medium` — the site states a remote/hybrid policy but you couldn't open a posting
    confirming the region.
  - `low` — you couldn't access the careers page/postings (403, JS-only, empty).
  The merge step never lets a lower confidence overwrite a higher one, so an honest
  `low` is safe — a dishonest `high` quietly blocks future re-checks.
- **`description`** — one sentence (≤ ~25 words) on what the company does; for
  discovery, note whether it's an EO/satellite/geospatial company.
- **`note`** — `""` normally. Flag acquired/defunct/renamed (name the acquirer), a
  dead careers link you couldn't re-resolve, a pivot away from EO, or (discovery) a
  likely duplicate or a candidate you couldn't confirm exists (set status `unknown`
  so the orchestrator can drop it).

## Output instructions (cost-critical)

- Write the JSON **array** to `companies/_inbox/<batch>.json` (the orchestrator
  tells you the batch name, e.g. `refresh_2.json` / `disc_3.json`). Write **one
  object per input line — never drop one**; a status line that claims more than the
  file contains is the failure we re-run for.
- Do **not** print the JSON back. Your final message is ONE status line, e.g.
  `refresh_2: 18 verified, 2 status changes, 1 remote change`.
