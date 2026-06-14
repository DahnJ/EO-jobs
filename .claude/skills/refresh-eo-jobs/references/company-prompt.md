# Per-company subagent prompt template

Dispatch one subagent per company (Agent tool, `general-purpose`). Fill in the
CURRENT DATA from the CSV. This template was validated on a live sample run.

---

You are verifying one Earth Observation company's directory entry. Use the
WebFetch tool only (the orchestrator handles a browser fallback separately). Be
conservative: only suggest a field change when the page clearly contradicts the
current value.

CURRENT DATA:
- Name: {Name}
- Description: "{Description}"
- Website: {Website}
- Jobs site: {Jobs site}
- Locations: {Locations}
- Remote: {Remote}

TASKS:
1. WebFetch the Website. Alive? If it redirects, note the new URL. (If the
   stored Website is a social URL rather than a homepage, propose the real
   homepage.)
2. WebFetch the Jobs site. Alive? Does it list open roles? If it 404s or
   redirects, note the current careers URL.
3. Check whether Description and Locations are still accurate per the site.
4. Determine the REMOTE policy by reading the careers/jobs page: remote /
   hybrid / remote-friendly, or onsite-only? Read between the lines (job
   locations tagged "Remote"/"Hybrid", multiple country offices, explicit WFH
   statements). Record the exact evidence (short quote or what you saw) and
   which page it came from.

If a page returns HTTP 403 or an empty body, say so explicitly (do NOT guess) —
the orchestrator will retry it in a browser.

Return ONLY this structured report, nothing else:

```
COMPANY: {Name}
WEBSITE: <ok | dead | redirect→URL | suggest homepage: URL>
JOBS_SITE: <ok | dead | redirect→URL | 403-blocked> | roles_visible: <yes/no/unknown>
DESCRIPTION: <keep | suggest: "..." (why)>
LOCATIONS: <keep | suggest: "..." (why)>
REMOTE: current="{Remote}" → suggested="<value>" | confidence=<high|med|low> | evidence="<quote/observation>" (source: <page>, <YYYY-MM>)
NOTES: <defunct/acquired/renamed/other, or "none">
CONFIDENCE_OVERALL: <high|med|low — could you fetch the pages at all?>
```
