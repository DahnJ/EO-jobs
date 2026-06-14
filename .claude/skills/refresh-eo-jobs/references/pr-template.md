# PR body template

Keep it to the changelog below — no test-plan / caveats sections. Omit any
section that has no entries. The **Remote** section is what the reviewer checks
closely, so always include its evidence.

```markdown
Refresh of the EO company directory (agent run, <YYYY-MM>). Verified against
company sites/careers pages via WebFetch + browser fallback.

### Link health
- <Company> — <dead/redirect>: <old> → <new>

### Locations
- <Company> — <what changed and why>

### Remote (review closely — with evidence)
- <Company>: <old> → <new> `<confidence>` — "<evidence quote/observation>" (<source page>)

### New companies
- [NEW] <Company> — <one-line rationale> (source: <where found>)

### Could not verify (left unchanged)
- <Company> — <reason, e.g. site returned 502 / both fetch + browser blocked>
```
