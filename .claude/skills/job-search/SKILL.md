---
name: job-search
description: Find CURRENT open jobs at companies in the EO-jobs database that a person can actually do from a given place (e.g. "remote from Prague") in a given field (software, data, ML, GIS dev). Use whenever the user asks "which of these companies are hiring X", "find remote jobs I can do from <city/country>", "what's open at Overstory", or wants a shortlist of postings — even if they don't say "job search". Not for updating company records (see refresh-eo-jobs).
---

# Job search

Turns the company DB into a shortlist of real postings the user can apply to. The
hard part is not finding postings — it's reading **where each one can be done**.
A company-level `remote: "Yes"` usually means "remote within the countries we
employ in", and the posting is the only place that list appears.

## Inputs

Ask only if missing: the user's **location** (city + country) and **fields**
(e.g. software / data / ML / geospatial dev). Default to excluding sales, ops,
hardware and field roles.

## 1. Pick candidate companies from the DB

Read `companies/*.md` frontmatter. Keep `status: active` + `listed: true`, and
either an office in the user's country (match `locations`) or a `remote` value
that could include them: a plain `Yes`, or a region that contains their country
(`Europe`, `EU`, `EMEA`, `Global`…). Drop regions that exclude them (`Yes (US)`).
Expect ~60 candidates for "remote from Prague"; that's fine.

## 2. Query ATS job APIs first (no LLM, exact locations)

Most boards render in JavaScript, so WebFetch sees an empty page — but the big
ATSs have public JSON APIs that return every posting with its location list.
Find the board from the careers page (`curl -sL <careers> | grep -oiE
'(ashbyhq|greenhouse|lever|personio|workable|recruitee)[^"]*'`), then:

| ATS | Endpoint | Where the location is |
|---|---|---|
| Ashby | `https://api.ashbyhq.com/posting-api/job-board/<org>` | `location` + `secondaryLocations[].location`, `isRemote` |
| Greenhouse | `https://boards-api.greenhouse.io/v1/boards/<org>/jobs?content=true` | `location.name`, body text |
| Lever | `https://api.lever.co/v0/postings/<org>?mode=json` | `categories.location`, `workplaceType` |
| Personio | `https://<org>.jobs.personio.de/xml` | `<office>` |
| Recruitee | `https://<org>.recruitee.com/api/offers/` | `location`, `remote` |

An explicit country list is the answer: if the user's country isn't on it, the
role is `no` even when it says "Remote" (Overstory's remote roles list 11
countries and omit Czechia).

## 3. WebFetch the rest (parallel Haiku agents)

For companies without a known ATS, dispatch Haiku subagents, ~12 companies each,
≤5 at once. Each fetches the careers page, **opens every fitting posting**, and
writes JSON `{company, title, url, location_text, prague_ok, evidence}` to the
scratchpad. Each must also write one row per company with no hit, saying why
(`no fitting roles` vs `careers unreachable`) — "0 jobs" from an agent that
couldn't read the board is not evidence.

## 4. Browser fallback with Claude in Chrome

Every `careers unreachable` row (JS-only boards, iframes, "Show more" pagination,
LinkedIn guest pages, PDFs) goes to the real browser. Load the Chrome tools in one
`ToolSearch` call (see the claude-in-chrome MCP instructions), then **one tab at a
time** — there is one shared Chrome:

- `navigate` to the board, then `get_page_text`; if it returns nothing (BambooHR,
  Workday), use `read_page` or a screenshot.
- Click "Show more" / open each fitting posting; read the location from the
  posting body, not the board's "Remote" chip.
- Each new domain needs the user to approve a prompt. If they can't click
  approvals right now, skip this step and list those companies as unchecked.

## 5. Classify and report

- `yes` — posting names the user's country/city, or "remote" in a region that
  contains it (EU, EMEA, CET, anywhere).
- `likely` — "remote" with no region, at a company with an entity in the user's
  region.
- `unclear` — "remote" with no region and no known entity there: worth asking.
- `no` — restricted elsewhere. Mention notable near misses (e.g. hybrid in a
  nearby city) in one line.

Report as short sections: **Likely/yes** (title, company, link, the location
quote), **Unclear — ask first**, **Near misses**, **Not checked** (and why).
Every job listed must be one a tool actually returned — never infer a posting.

## 6. Feed findings back

A posting often reveals the real remote region ("Remote — US only"). Write those
as refresh inbox records (`remote`, `remote_evidence`, `remote_confidence: high`)
and run `just merge "job-search YYYY-MM"` so the README's Remote column gets more
precise.
