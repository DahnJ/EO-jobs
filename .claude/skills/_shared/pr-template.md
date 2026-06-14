# PR body template

Only open a PR if explicitly asked. Keep it to the changelog below — no test-plan
/ caveats sections. Omit any section that has no entries. The **Remote** section is
what the reviewer checks closely, so always include its evidence.

```markdown
Refresh of the EO company directory (agent run, <YYYY-MM>). Verified against
company sites/careers pages via WebFetch (+ browser fallback where used). DB now
<N> companies; <M> listed in the README.

### Link / status changes
- <Company> — <active→acquired / website redirect / careers URL fixed>

### Locations
- <Company> — <what changed and why>

### Remote (review closely — with evidence)
- <Company>: <old> → <new> — "<evidence quote/observation>" (<source page>)

### New companies (discovery)
- [NEW] <Company> — <one-line rationale> (source: <where found>)

### Reclassified / excluded from README
- <Company> — <commercial-eo → consultancy/nonprofit/not-eo, or acquired>

### Could not verify (left unchanged)
- <Company> — <reason, e.g. site 502 / both fetch + browser blocked>
```
