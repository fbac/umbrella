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
[ -r "$SPEC" ] || { echo "render.sh: cannot read spec $SPEC" >&2; exit 1; }
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
if [ -n "$PLAN" ] && [ ! -r "$PLAN" ]; then
  echo "render.sh: cannot read plan $PLAN" >&2; exit 1
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
