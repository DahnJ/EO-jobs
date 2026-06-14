# Classification subagent prompt (BROAD EO scope)

Classification decides each company's `type`, which drives README inclusion.
The commercial-EO boundary is fuzzy, so an agent decides it from the stored
description — not keyword matching. Build the input with `just class-input`
(a `{slug, name, desc, body}` JSONL), split into batches of ~175, dispatch one
**Haiku** subagent per batch. Output `[{slug, type, reason}]` to
`companies/_inbox/class_N.json`; `just readme` applies it.

**Standing decision: use the BROAD definition.** A previous strict pass that
required the *product* to be EO wrongly excluded companies that build on EO data.

---

You are classifying companies for an Earth Observation (EO) directory that uses a
BROAD definition of "in scope". Read the file <BATCH PATH> — one JSON object per
line: {slug, name, desc, body}. Output one result for EVERY line.

Assign exactly one "type":
- "commercial-eo": IN SCOPE. Use whenever the company uses Earth Observation /
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
  Trimble, Hexagon, L3Harris, GMV, NV5, Google, Microsoft).
- "nonprofit": an NGO, foundation, academic/research nonprofit, or government body.
- "not-eo": genuinely NOT related to EO at all — does not use satellite/aerial/
  remote-sensing data as a core input (business coaching, identity/KYC, farm-
  management or supply-chain software with no imagery, generic AI).

Bias toward "commercial-eo" for anything that genuinely touches EO/satellite/
aerial data. Reserve "not-eo" for clearly unrelated businesses.

OUTPUT: write a JSON array to companies/_inbox/class_N.json (your batch number),
each element {"slug": "...", "type": "...", "reason": "<=12 words"}. Do NOT print
it back. Final message = ONLY "class_N: M classified" where M equals the line count.
