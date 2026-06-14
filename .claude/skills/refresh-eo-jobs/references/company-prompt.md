# Verification subagent prompt template

Dispatch one **Haiku** subagent per batch of ~18 companies (Agent tool,
`model: haiku`, `general-purpose`). The agent fetches each company, writes a JSON
array to its inbox file, and returns only a one-line status. This serves both
Stage 1 (refresh existing) and Stage 2 (discover new) — see the two variants below.

The output keys match what `merge_inbox.py` consumes:
`slug, name, status, website, careers_url, locations, remote, remote_evidence, description, note`.

---

You are verifying Earth Observation company entries. For EACH company in the list
below, use WebFetch on its website (and the careers/jobs page if you can find one)
to determine the facts. Be efficient: at most 1-2 WebFetch calls per company. If a
site fails to load after 1 retry, record what you can and set status "unknown".

For each company produce a JSON object with these exact keys:

- "slug": lowercase the company name, replace every run of non-alphanumeric chars
  with a single hyphen, strip leading/trailing hyphens.
  (e.g. "Salo Sciences" → "salo-sciences", "20tree.ai" → "20tree-ai")
- "name": the company name as given.
- "status": one of "active" | "acquired" | "defunct" | "renamed" | "unknown".
- "website": the canonical homepage URL (https).
- "careers_url": the careers/jobs page URL if one exists, else "" (empty string).
- "locations": array of strings, HQ + major offices (e.g. ["San Francisco, US"]).
  [] if unknown.
- "remote": one of "Yes" | "No" | "Hybrid" | "" (empty if you cannot tell). Read
  between the lines from job listings / careers-page language.
- "remote_evidence": one short sentence quoting/paraphrasing what on the page
  indicates the remote policy. "" if none.
- "description": one sentence (≤ ~25 words) on what the company does, focused on
  whether it is an Earth Observation / satellite / geospatial company.
- "note": "" normally. Use it to flag if the company is NOT earth-observation
  (write "not an EO company" — classify.py keys on that), is acquired/defunct, or
  is a duplicate of another entry.

OUTPUT INSTRUCTIONS (important for cost):
- Write the JSON array of all objects to: companies/_inbox/<BATCH>.json
- Do NOT print the JSON back. Your final message must be ONLY one line like:
  "<BATCH>: 18 companies written, 13 active, 3 unknown".

Companies to verify:
<Name|website, one per line>

---

## Variant: Stage 1 (refresh existing)

Provide the CURRENT stored values per company (name, website, careers_urls,
locations, remote) so the agent can be conservative — only overriding a field when
the live page clearly contradicts it. Inbox file: `refresh_N.json`. Existing slugs
will be updated in place by `merge_inbox.py`.

## Variant: Stage 2 (discovery)

Companies are new (post-dedup). Inbox file: `disc_N.json`. For candidates with no
URL, or where a quick web search can't confirm the company exists, set status
"unknown" and say so in `note` (the orchestrator can then drop it). Flag likely
duplicates of known companies in `note`.
