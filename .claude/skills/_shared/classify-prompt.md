# Classification subagent prompt (BROAD EO scope)

Classification decides each company's `type` and, for the rare company that needs
it, an `unlisted_reason`. Type alone does not decide README inclusion: only `not-eo`
keeps a company off, and every other type is listed with a label unless it is
`commercial-eo`. The EO boundary is fuzzy, so an agent decides it from the stored
description — not keyword matching. Build the input with `just class-input`
(a `{slug, name, desc, body, unlisted_reason?}` JSONL), split into batches of ~175,
dispatch one **Haiku** subagent per batch. Output
`[{slug, type, reason, unlisted_reason?}]` to `companies/_inbox/class_N.json`;
`just readme` applies it. A verdict replaces the stored `unlisted_reason`, and a
verdict without one clears it.

**Standing decision: use the BROAD definition.** A previous strict pass that
required the *product* to be EO wrongly excluded companies that build on EO data.

---

You are classifying companies for an Earth Observation (EO) directory that uses a
BROAD definition of "in scope". Read the file <BATCH PATH> — one JSON object per
line: {slug, name, desc, body, and unlisted_reason if one is stored}. Output one
result for EVERY line.

Assign exactly one "type":
- "commercial-eo": Use whenever the company uses Earth Observation /
  satellite / aerial / remote-sensing data as a CORE INPUT to its product or
  service — even if the end product is climate risk, parametric insurance, carbon
  measurement (MRV), precision agriculture, emissions/methane monitoring, flood/
  wildfire risk, or an EO analytics/ML software platform. If EO data is central,
  it belongs here.
- "consultancy": primarily a services/advisory/consulting firm (does client
  projects) rather than a product/data company.
- "reseller": primarily resells/distributes other providers' satellite/EO data.
- "software": ONLY a generic GIS / photogrammetry / point-cloud / CAD / mapping
  TOOL that is not itself an EO-data product. If it is an EO imagery/analytics
  platform, use commercial-eo.
- "conglomerate": a large multi-division company where EO is a small part (Airbus,
  Trimble, Hexagon, L3Harris, GMV, NV5, Google, Microsoft). This is a label, not an
  exclusion: a conglomerate with real EO work stays in the directory.
- "nonprofit": an NGO, foundation, academic/research nonprofit, or government body.
- "not-eo": genuinely NOT related to EO at all — does not use satellite/aerial/
  remote-sensing data as a core input (business coaching, identity/KYC, farm-
  management or supply-chain software with no imagery, generic AI).

Bias toward "commercial-eo" for anything that genuinely touches EO/satellite/
aerial data. Reserve "not-eo" for clearly unrelated businesses.

Optionally add "unlisted_reason" to keep a company off the README. Use it only for a
company with no meaningful EO business, or with no way to reach EO roles from its
careers link (e.g. Google, Microsoft). Having no open job today is not a reason. Keep
a stored reason unless the line's text clearly contradicts it. Leave it out for
everyone else.

OUTPUT: write a JSON array to companies/_inbox/class_N.json (your batch number),
each element {"slug": "...", "type": "...", "reason": "<=12 words"}, plus
"unlisted_reason": "<=12 words" where it applies. Do NOT print it back. Final message = ONLY "class_N: M classified" where M equals the line count.
