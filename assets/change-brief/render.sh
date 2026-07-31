#!/usr/bin/env bash
# render.sh — assemble a change brief HTML from markdown sources.
# POSIX bash + coreutils only. No node, no npm, no network at render time.
#
#   render.sh SPEC.md [PLAN.md] -o OUT.html [-t TEMPLATE.html] [-V VENDOR_DIR]
#
# Omit PLAN.md to render the spec-gate brief: the Plan section becomes an
# explicit "not yet written — changes are free right now" callout.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="${BRIEF_TEMPLATE:-$HERE/template.html}"
VENDOR="${BRIEF_VENDOR:-$HERE/vendor}"
SPEC=""; PLAN=""; OUT=""

# Never leave a half-written brief on disk: a truncated file that opens blank
# is worse than no file, because it looks like a render that succeeded.
cleanup() { [ -n "${OUT:-}" ] && [ -n "${FAILED:-}" ] && rm -f "$OUT"; rm -rf "${TMP:-}"; }
die() { FAILED=1; echo "render.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    # Guard the value before consuming it: under `set -e`, `shift 2` with only
    # the flag left (no value after it) returns non-zero and kills the script
    # before any message can print — the one failure mode this script's
    # fail-loudly design (see cleanup()/die() above) must never have.
    -o) [ $# -ge 2 ] || { echo "render.sh: $1 requires a value" >&2; exit 1; }; OUT="$2"; shift 2 ;;
    -t) [ $# -ge 2 ] || { echo "render.sh: $1 requires a value" >&2; exit 1; }; TPL="$2"; shift 2 ;;
    -V) [ $# -ge 2 ] || { echo "render.sh: $1 requires a value" >&2; exit 1; }; VENDOR="$2"; shift 2 ;;
    -*) echo "render.sh: unknown option $1" >&2; exit 1 ;;
    *)  if [ -z "$SPEC" ]; then SPEC="$1"
        elif [ -z "$PLAN" ]; then PLAN="$1"
        else echo "render.sh: unexpected argument $1" >&2; exit 1; fi
        shift ;;
  esac
done

[ -n "$SPEC" ] || { echo "usage: render.sh SPEC.md [PLAN.md] -o OUT.html" >&2; exit 1; }
# A directory (or other non-regular file) passes -r on most systems, so
# strip_bom's sed would run against it, print zero bytes with no error, and
# the render would report success on an empty section. Require a regular
# file, not merely a readable path; -f follows symlinks, so a symlink to a
# real spec still passes.
[ -f "$SPEC" ] && [ -r "$SPEC" ] || { echo "render.sh: cannot read spec $SPEC" >&2; exit 1; }
# strip_h1's blank-line and heading regexes do not account for a trailing
# \r, so a CRLF spec silently skips the H1 strip instead of failing — the
# same trap the template guard below exists for. Reject here, once, before
# anything downstream reads the file.
! grep -q $'\r$' "$SPEC" || { echo "render.sh: spec $SPEC has CRLF line endings; convert to LF before rendering" >&2; exit 1; }
[ -r "$TPL"  ] || { echo "render.sh: cannot read template $TPL" >&2; exit 1; }
# Task 6 injects into this template with sed addresses anchored to a whole
# line (^PLACEHOLDER$). A CRLF-terminated file puts a stray \r before that
# anchor's end-of-line, so a placeholder that is visibly alone on its own
# line still fails the anchor — and would otherwise abort downstream with a
# confusing "must be alone on its line" message that names the wrong culprit.
# Catch the real cause here, once, for the whole file.
! grep -q $'\r$' "$TPL" || { echo "render.sh: template $TPL has CRLF line endings; convert to LF before rendering" >&2; exit 1; }
# A supplied-but-unreadable plan must fail loudly. Falling through to the
# pending callout would tell the human "no plan exists yet" when one does.
# Same regular-file and CRLF requirements as the spec, above.
if [ -n "$PLAN" ]; then
  [ -f "$PLAN" ] && [ -r "$PLAN" ] || { echo "render.sh: cannot read plan $PLAN" >&2; exit 1; }
  ! grep -q $'\r$' "$PLAN" || { echo "render.sh: plan $PLAN has CRLF line endings; convert to LF before rendering" >&2; exit 1; }
fi
[ -r "$VENDOR/marked.min.js"  ] || { echo "render.sh: missing $VENDOR/marked.min.js"  >&2; exit 1; }
[ -r "$VENDOR/mermaid.min.js" ] || { echo "render.sh: missing $VENDOR/mermaid.min.js" >&2; exit 1; }

# Assert every placeholder is PRESENT before substituting, counting actual
# OCCURRENCES rather than matching lines: `grep -c` counts lines, so two
# copies of the same placeholder on one physical line still read as one and
# sail through. Checking only that none survives passes a template with one
# deleted, yielding an empty brief and a zero exit status.
for ph in __TITLE_B64__ __SOURCES_B64__ __GENERATED__ __DIAG_B64__ __PLANSTATE__ __VENDOR_JS__ __BRIEF_B64__; do
  n=$(grep -o "$ph" "$TPL" | wc -l | tr -d ' ' || true)
  [ "$n" -ne 0 ] || { echo "render.sh: template $TPL is missing $ph" >&2; exit 1; }
  # Exactly once. A template comment documenting a placeholder is a second
  # occurrence; with the injection addresses anchored it would survive
  # substitution and abort late with a confusing message.
  [ "$n" -eq 1 ] || { echo "render.sh: $ph appears $n times in $TPL; it must appear exactly once (do not name it in comments)" >&2; exit 1; }
done
grep -q '^__VENDOR_JS__$' "$TPL" || { echo "render.sh: __VENDOR_JS__ must be alone on its line" >&2; exit 1; }
grep -q '^__BRIEF_B64__$'  "$TPL" || { echo "render.sh: __BRIEF_B64__ must be alone on its line"  >&2; exit 1; }

[ -n "$OUT" ] || OUT="docs/briefs/$(basename "${SPEC%.md}").html"
mkdir -p "$(dirname "$OUT")"

TMP="$(mktemp -d)"
trap cleanup EXIT

b64() { base64 < "$1" | tr -d '\n'; }              # GNU -w0 is absent on macOS
b64s(){ printf '%s' "$1" | base64 | tr -d '\n'; }
digest() {
  if   command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" | cut -c1-8
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-8
  else echo "nohash"; fi
}

# ---- payload ---------------------------------------------------------------
# Both documents' H1 is dropped: the spec's title is already the masthead, and
# the plan's would be a second H1 mid-document. Bodies nest under a synthesized
# "## Plan" so tasks land in the index under Plan rather than under whichever
# H2 the spec happened to end on.
#
# The strip is first-line-only. A fence-unaware "first /^# / anywhere" rule
# silently deletes a `# comment` line from a bash fence when the document has
# no H1 — verified. Both document templates put the H1 on line 1.
# Skip a UTF-8 BOM, leading blank lines, and a YAML front-matter block before
# testing for the H1. All three defeat a naive NR==1 rule, and a leading blank
# line is an ordinary editor artifact rather than a malformed document. A BOM
# also stops CommonMark seeing the line as a heading at all, so it is removed
# outright rather than just skipped.
strip_bom() { sed $'1s/^\xef\xbb\xbf//' "$1"; }
has_front_matter() {
  head -n 1 "$1" | grep -q '^---[[:space:]]*$' || return 1
  awk 'NR > 1 && NR <= 51 && /^---[ \t]*$/ { found = 1; exit }
       NR > 1 && NR <= 51 && !/^[ \t]*$/ && !/^[A-Za-z_][A-Za-z0-9_.-]*:/ { exit }
       END { exit !found }' "$1"
}
strip_h1() {
  strip_bom "$1" > "$TMP/nobom.md"
  fmflag=0
  has_front_matter "$TMP/nobom.md" && fmflag=1
  awk -v fm="$fmflag" '
    BEGIN { started = 0; infm = 0; fmdone = 0 }
    fm && !fmdone && !infm && NR == 1 && /^---[ \t]*$/ { infm = 1; next }
    infm && /^---[ \t]*$/ { infm = 0; fmdone = 1; next }
    infm { next }
    !started && /^[ \t]*$/ { print; next }
    !started { started = 1; if ($0 ~ /^ {0,3}# /) next }
    { print }
  ' "$TMP/nobom.md"
}

strip_h1 "$SPEC" > "$TMP/payload.md"
# U+2060 WORD JOINER marks the heading render.sh synthesized. The page finds
# the plan region by it and proves the parse survived. Matching a heading named
# "Plan" is guesswork: either document may contain its own Plan section, and
# both "first match" and "last match" misplaced the graph.
printf '\n\n## Plan\342\201\240\n\n' >> "$TMP/payload.md"

if [ -n "$PLAN" ]; then
  strip_h1 "$PLAN" >> "$TMP/payload.md"
  PLAN_STATE="plan attached"; PLAN_STATE_KEY="attached"
else
  cat >> "$TMP/payload.md" <<'PENDING'
> [!PENDING]
> You are reviewing the **why**, the **existing system**, and the **design** — before any
> implementation plan exists. Changing the shape of this feature costs nothing right now.
> After the plan is written, the same change costs a plan rewrite.
>
> Read the preceding sections and push back before approving.
PENDING
  PLAN_STATE="plan pending"; PLAN_STATE_KEY="pending"
fi

# Neutralise line-start "<!--" outside fences. CommonMark HTML-block type 2
# runs from such a line to the closing "-->" or, absent one, to EOF — so an
# unterminated comment in prose silently deletes every section after it,
# including the pending callout, with exit 0 and no page error. Escaping it
# costs nothing in fidelity: raw HTML is escaped at parse time anyway, so a
# terminated comment already rendered as literal text.
#
# Escaping runs ONLY when the payload actually has a dangling opener. Escaping
# unconditionally corrupts balanced comments inside indented code samples,
# which a spec about HTML templating will contain.
SCAN="$(dirname "$0")/scan.awk"
[ -r "$SCAN" ] || { echo "render.sh: missing $SCAN" >&2; exit 1; }

UNBALANCED="$(awk -v mode=dangle -f "$SCAN" "$TMP/payload.md")"
awk -v mode=diag -f "$SCAN" "$TMP/payload.md" > "$TMP/diag.txt"

awk -v mode=escape -v unbalanced="$UNBALANCED" -f "$SCAN" \
    "$TMP/payload.md" > "$TMP/payload.esc.md" && mv "$TMP/payload.esc.md" "$TMP/payload.md"

while read -r w; do [ -n "$w" ] && echo "render.sh: warning: $w" >&2; done < "$TMP/diag.txt"

# ---- provenance ------------------------------------------------------------
# Hash the working-tree bytes that were actually embedded. A git blob SHA would
# certify the committed version while the payload carries uncommitted edits.
SOURCES="$(basename "$SPEC")@$(digest "$SPEC")"
[ -n "$PLAN" ] && SOURCES="$SOURCES · $(basename "$PLAN")@$(digest "$PLAN")"
SOURCES="$SOURCES · $PLAN_STATE"

GENERATED="$(date -u '+%Y-%m-%d %H:%M UTC')"
TITLE="$(strip_bom "$SPEC" | awk '/^ {0,3}# /{ sub(/^ *# */,""); print; exit }')"
[ -n "$TITLE" ] || TITLE="$(basename "${SPEC%.md}")"

# ---- encode ----------------------------------------------------------------
# Title and sources travel as base64 too. Interpolating them into sed would
# break on '|', swallow '\', and let '&' re-inject the matched pattern.
b64 "$TMP/payload.md" > "$TMP/payload.b64"
cat "$VENDOR/marked.min.js" > "$TMP/vendor.js"
printf '\n;\n' >> "$TMP/vendor.js"
cat "$VENDOR/mermaid.min.js" >> "$TMP/vendor.js"

sed -e "s|__TITLE_B64__|$(b64s "$TITLE")|g" \
    -e "s|__SOURCES_B64__|$(b64s "$SOURCES")|g" \
    -e "s|__GENERATED__|$GENERATED|g" \
    -e "s|__DIAG_B64__|$(b64 "$TMP/diag.txt")|g" \
    -e "s|__PLANSTATE__|$PLAN_STATE_KEY|g" \
    "$TPL" > "$TMP/step1.html"

# ---- large injections ------------------------------------------------------
# Addresses are ANCHORED. An unanchored /__VENDOR_JS__/ also matches a template
# comment that merely mentions the placeholder, injecting the 3.3MB bundle
# twice — verified.
sed -e "/^__VENDOR_JS__$/{" -e "r $TMP/vendor.js" -e "d" -e "}" "$TMP/step1.html" > "$TMP/step2.html"
sed -e "/^__BRIEF_B64__$/{"  -e "r $TMP/payload.b64" -e "d" -e "}" "$TMP/step2.html" > "$OUT"

# Exact names: a generic /__[A-Z_]*__/ also matches the underscore runs inside
# the minified vendor bundle.
if grep -qE '__(TITLE_B64|SOURCES_B64|GENERATED|DIAG_B64|PLANSTATE|VENDOR_JS|BRIEF_B64)__' "$OUT"; then
  die "unsubstituted placeholder remains in $OUT"
fi
tpl_bytes=$(wc -c < "$TPL"); out_bytes=$(wc -c < "$OUT")
[ "$out_bytes" -gt "$tpl_bytes" ] || die "output ($out_bytes B) is not larger than template ($tpl_bytes B)"

echo "$OUT"
