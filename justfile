# EO-jobs deterministic pipeline.
# Agent judgment lives in the skills; these recipes are the mechanical spine —
# runnable by a human, by CI, or by a skill. `uv run` manages the environment.

# list recipes
default:
    @just --list

# full deterministic refresh: apply classification verdicts, then rebuild README
readme: classify generate

# apply type verdicts from companies/_inbox/class_*.json (or just recompute `listed`)
classify:
    uv run python classify.py

# rebuild README.md from the DB (listed companies only)
generate:
    uv run python generate_readme.py

# merge verified inbox JSON into the DB; SOURCE tags newly-created files
merge source="discovery-sweep":
    uv run python merge_inbox.py --source "{{source}}"

# apply confirmed duplicate merges recorded in known_duplicates.json
dedup:
    uv run python dedup.py

# link-rot sweep over website + careers URLs (listed companies by default)
check args="--listed-only":
    uv run python check_links.py {{args}}

# one-shot data hygiene: normalize `remote` values + backfill location flags
fixup:
    uv run python fixup_data.py

# backfill a flag emoji on every location that lacks one (locations must have flags)
flags:
    uv run python flags.py

# DB summary (counts by status / source / listed)
stats:
    uv run python db.py

# build the compact {slug,name,desc,body} JSONL a classification agent reads
class-input out="/tmp/class_in.jsonl":
    uv run python -c "import db, json; \
        rows=[{'slug':p.stem,'name':(r:=db.parse(p.read_text()))['name'],'desc':r.get('description',''),'body':r.get('body','').replace(chr(10),' ')[:300]} for p in sorted(db.DB.glob('*.md'))]; \
        open('{{out}}','w').write('\n'.join(json.dumps(c,ensure_ascii=False) for c in rows)+'\n'); \
        print(len(rows),'companies ->','{{out}}')"

# build the compact slug<TAB>name<TAB>domain index a dedup agent reads
dedup-index out="/tmp/company_index.tsv":
    uv run python -c "import db; from urllib.parse import urlparse; \
        rows=[f\"{p.stem}\t{(r:=db.parse(p.read_text()))['name']}\t{urlparse(r.get('website','')).netloc.replace('www.','')}\" for p in sorted(db.DB.glob('*.md'))]; \
        open('{{out}}','w').write('\n'.join(rows)+'\n'); print(len(rows),'companies ->','{{out}}')"
