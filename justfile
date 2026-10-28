# EO-jobs deterministic pipeline (Clojure).
# Agent judgment lives in the skills; these recipes are the mechanical spine —
# runnable by a human, by CI, or by a skill.

export JAVA_HOME := "/opt/homebrew/opt/openjdk"

run := "clojure -M:run"

# list recipes
default:
    @just --list

# full deterministic refresh: apply classification verdicts, then rebuild README
readme: classify generate

# apply type verdicts from companies/_inbox/class_*.json (or just recompute `listed`)
classify:
    {{run}} classify

# rebuild README.md from the DB (listed companies only)
generate:
    {{run}} readme

# merge verified inbox JSON into the DB; SOURCE tags newly-created files
merge source="discovery-sweep":
    {{run}} merge --source "{{source}}"

# apply confirmed duplicate merges recorded in known_duplicates.json
dedup:
    {{run}} dedup

# link-rot sweep over website + careers URLs (listed companies by default)
check args="--listed-only":
    {{run}} check-links {{args}}

# detect acquisitions/rebrands: listed sites that now redirect to a different domain
redirects:
    {{run}} check-redirects

# one-shot data hygiene: normalize `remote` values + backfill location flags
fixup:
    {{run}} fixup

# backfill a flag emoji on every location that lacks one (locations must have flags)
flags:
    {{run}} flags

# DB summary (counts by status / source / listed)
stats:
    {{run}} stats

# build the compact {slug,name,desc,body} JSONL a classification agent reads
class-input out="/tmp/class_in.jsonl":
    {{run}} class-input --out "{{out}}"

# build the compact slug<TAB>name<TAB>domain index a dedup agent reads
dedup-index out="/tmp/company_index.tsv":
    {{run}} dedup-index --out "{{out}}"
