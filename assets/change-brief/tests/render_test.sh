#!/usr/bin/env bash
# Shell-level assertions for render.sh. Coreutils, plus python3 to decode the
# base64 payload out of a rendered brief (see the payload() helper).
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"          # assets/change-brief
R="$(cd "$S/../.." && pwd)"                     # repo root
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok(){ printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s :: %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$3] got [$2]"; fi }

echo "== repo scaffold =="
grep -q '^docs/briefs/$' "$R/.gitignore" && ok "gitignore excludes docs/briefs/" \
  || no "gitignore excludes docs/briefs/" "missing"

echo "== vendor pinning =="
for v in marked mermaid; do
  [ -r "$S/vendor/$v.min.js" ] && ok "vendor/$v.min.js present" \
    || no "vendor/$v.min.js present" "missing"
done
chk "marked is 12.0.2" \
  "$(grep -c 'marked v12\.0\.2' "$S/vendor/marked.min.js" 2>/dev/null || echo 0)" "1"
got_sha=$(shasum -a 256 "$S/vendor/marked.min.js" 2>/dev/null | cut -d' ' -f1)
chk "marked sha256 pinned" "$got_sha" \
  "15fabce5b65898b32b03f5ed25e9f891a729ad4c0d6d877110a7744aa847a894"
got_sha=$(shasum -a 256 "$S/vendor/mermaid.min.js" 2>/dev/null | cut -d' ' -f1)
chk "mermaid sha256 pinned" "$got_sha" \
  "61b335a46df05a7ce1c98378f60e5f3e77a7fb608a1056997e8a649304a936d6"

echo "== scan.awk =="
SC="$S/scan.awk"

printf '# Title\n\nbody\n\n# Stray H1\n\nmore\n' > "$W/h1.md"
chk "stray ATX H1 flattened to h4" \
  "$(awk -v mode=escape -f "$SC" "$W/h1.md" | grep -c '^#### ')" "2"

printf 'Setext Heading\n==============\n\nbody\n' > "$W/setext.md"
chk "setext H1 flattened to h4" \
  "$(awk -v mode=escape -f "$SC" "$W/setext.md" | grep -c '^#### Setext Heading$')" "1"

printf 'text\n\n<!-- never closed\n\n## Later\n' > "$W/dangle.md"
chk "dangling comment detected" "$(awk -v mode=dangle -f "$SC" "$W/dangle.md")" "1"
chk "dangling comment escaped with indent intact" \
  "$(awk -v mode=escape -v unbalanced=1 -f "$SC" "$W/dangle.md" | grep -c '^&lt;!--')" "1"

printf 'text\n\n--> stray arrow in prose\n\n<!-- never closed\n' > "$W/order.md"
chk "stray --> does not balance a later opener" \
  "$(awk -v mode=dangle -f "$SC" "$W/order.md")" "1"

printf 'a\n\n```html\n<!-- balanced -->\n```\n\nb\n' > "$W/fenced.md"
chk "comment inside a fence is not escaped" \
  "$(awk -v mode=escape -v unbalanced=1 -f "$SC" "$W/fenced.md" | grep -c '^&lt;!--')" "0"

printf -- '- step:\n\n  ```html\n  <!-- keep -->\n  ```\n' > "$W/indent.md"
chk "indented fence comment keeps its indentation" \
  "$(awk -v mode=escape -v unbalanced=1 -f "$SC" "$W/indent.md" | grep -c '^  <!-- keep -->$')" "1"

printf 'a\n\n```bash\necho hi\n' > "$W/openfence.md"
chk "unterminated fence reported" \
  "$(awk -v mode=diag -f "$SC" "$W/openfence.md" | grep -c 'Unterminated code fence')" "1"
chk "clean document produces no diagnostics" \
  "$(awk -v mode=diag -f "$SC" "$W/fenced.md" | wc -l | tr -d ' ')" "0"

echo "== scan.awk: CRLF fix, and the accepted list-lazy-setext gap =="

printf 'Heading\r\n=======\r\n\r\nbody\r\n' > "$W/crlf.md"
chk "CRLF setext H1 flattened to h4" \
  "$(awk -v mode=escape -f "$SC" "$W/crlf.md" | grep -c '^#### Heading')" "1"

printf '> quoted\n===\n' > "$W/bq.md"
chk "blockquote setext-lookalike NOT flattened" \
  "$(awk -v mode=escape -f "$SC" "$W/bq.md" | grep -c '^> quoted$')" "1"
chk "blockquote setext-lookalike underline left intact" \
  "$(awk -v mode=escape -f "$SC" "$W/bq.md" | grep -c '^===$')" "1"

# List-item lazy setext continuation is an accepted gap (see scan.awk's
# header): a list item's first line, immediately followed by a bare
# underline, still reaches the DOM as an unflattened stray H1. These guard
# the gap's boundary rather than the gap itself, so a future change that
# silently starts (or stops) touching list-item lines is caught either way.
printf -- '- item one\n========\nmore\n' > "$W/list_gap.md"
chk "bullet list item + bare underline is left unchanged (accepted gap)" \
  "$(awk -v mode=escape -f "$SC" "$W/list_gap.md")" "$(cat "$W/list_gap.md")"

printf '1. item one\n========\nmore\n' > "$W/list_gap_ordered.md"
chk "ordered list item + bare underline is left unchanged (same accepted gap)" \
  "$(awk -v mode=escape -f "$SC" "$W/list_gap_ordered.md")" "$(cat "$W/list_gap_ordered.md")"

echo "== render.sh preconditions =="
printf '# T\n\n## Design\n\nbody\n' > "$W/spec.md"

"$S/render.sh" "$W/nonexistent.md" -o "$W/x.html" >/dev/null 2>"$W/err.txt"
chk "unreadable spec exits 1" "$?" "1"
grep -q 'cannot read spec' "$W/err.txt" && ok "  names the unreadable spec" \
  || no "  names the unreadable spec" "$(cat "$W/err.txt")"

"$S/render.sh" "$W/spec.md" "$W/nonexistent.md" -o "$W/x.html" >/dev/null 2>"$W/err.txt"
chk "unreadable plan exits 1" "$?" "1"
grep -q 'cannot read plan' "$W/err.txt" && ok "  names the unreadable plan" \
  || no "  names the unreadable plan" "$(cat "$W/err.txt")"
[ -f "$W/x.html" ] && no "  leaves no output file" "file exists" || ok "  leaves no output file"

"$S/render.sh" "$W/spec.md" -o "$W/x.html" -V "$W/novendor" >/dev/null 2>"$W/err.txt"
chk "missing vendor exits 1" "$?" "1"
grep -q 'missing .*marked\.min\.js' "$W/err.txt" && ok "  names the missing vendor file" \
  || no "  names the missing vendor file" "$(cat "$W/err.txt")"

echo "== render.sh: flag missing its value (defect round) =="
for flag in -o -t -V; do
  "$S/render.sh" "$W/spec.md" "$flag" >/dev/null 2>"$W/err.txt"
  chk "  $flag as last argument exits 1" "$?" "1"
  [ -s "$W/err.txt" ] && ok "  $flag as last argument writes a diagnostic" \
    || no "  $flag as last argument writes a diagnostic" "stderr was empty"
  grep -q -- "$flag" "$W/err.txt" && ok "  $flag as last argument names the flag" \
    || no "  $flag as last argument names the flag" "$(cat "$W/err.txt")"
done

echo "== render.sh: same-line duplicate placeholder (defect round) =="
cat > "$W/dup.html" <<'EOF'
<html><body>
__TITLE_B64____TITLE_B64__
__SOURCES_B64__
__GENERATED__
__DIAG_B64__
__PLANSTATE__
__VENDOR_JS__
__BRIEF_B64__
</body></html>
EOF
"$S/render.sh" "$W/spec.md" -o "$W/dup_out.html" -t "$W/dup.html" >/dev/null 2>"$W/err.txt"
chk "same-line duplicate placeholder exits 1" "$?" "1"
grep -q '__TITLE_B64__ appears 2 times' "$W/err.txt" && ok "  names the duplicate and its count" \
  || no "  names the duplicate and its count" "$(cat "$W/err.txt")"
[ -f "$W/dup_out.html" ] && no "  duplicate-placeholder template leaves no output file" "file exists" \
  || ok "  duplicate-placeholder template leaves no output file"

echo "== render.sh: CRLF template (defect round) =="
{ printf '<html><body>\r\n'
  printf '__TITLE_B64__\r\n__SOURCES_B64__\r\n__GENERATED__\r\n__DIAG_B64__\r\n__PLANSTATE__\r\n__VENDOR_JS__\r\n__BRIEF_B64__\r\n'
  printf '</body></html>\r\n'
} > "$W/crlf_tpl.html"
"$S/render.sh" "$W/spec.md" -o "$W/crlf_out.html" -t "$W/crlf_tpl.html" >/dev/null 2>"$W/err.txt"
chk "CRLF template exits 1" "$?" "1"
grep -qi 'crlf' "$W/err.txt" && ok "  names CRLF as the cause, not a false alone-on-its-line error" \
  || no "  names CRLF as the cause, not a false alone-on-its-line error" "$(cat "$W/err.txt")"

echo "== payload assembly =="
# Helper: decode the base64 payload out of a rendered brief.
#
# On ANY failure to produce a genuine payload -- the fixture was never
# built, is unreadable, has no data-brief attribute, or the attribute's
# base64 body is empty or corrupt -- writing nothing to stdout would let
# a downstream `grep -c PATTERN` on empty input legitimately print "0".
# That coincidentally equals the expected value of every assertion below
# that checks for an ABSENCE, letting it PASS on a fixture that was never
# built at all. Emit a fixed poison block instead: two lines matching
# each "must be absent" prefix this suite checks for (`# `, `> [!PENDING]`),
# so every such assertion sees a real, nonzero count and fails honestly.
# Two copies rather than one, so the one assertion here expecting that
# same prefix to appear EXACTLY once (the gate1 pending-callout check)
# still fails too, instead of being nudged from a correct 0 to a
# coincidentally "correct" 1.
payload(){ python3 - "$1" <<'PY'
import sys, re, base64

FAIL = (
    "# __PAYLOAD_FIXTURE_MISSING__\n"
    "# __PAYLOAD_FIXTURE_MISSING__\n"
    "> [!PENDING] __PAYLOAD_FIXTURE_MISSING__\n"
    "> [!PENDING] __PAYLOAD_FIXTURE_MISSING__\n"
)

try:
    h = open(sys.argv[1], encoding='utf-8').read()
    m = re.search(r'data-brief="([^"]*)"', h, re.S)
    if not m:
        raise ValueError('no data-brief attribute')
    text = base64.b64decode(re.sub(r'\s', '', m.group(1)), validate=True).decode('utf-8')
    if not text:
        raise ValueError('empty payload')
except Exception:
    sys.stdout.write(FAIL)
    sys.exit(1)

sys.stdout.write(text)
PY
}

printf '# Spec Title\n\n## Design\n\nbody\n' > "$W/s.md"
printf '# Plan One\n\n### Task 1: A\n\n**Depends on:** none\n\n- [ ] step\n' > "$W/p.md"

"$S/render.sh" "$W/s.md" -o "$W/g1.html" >/dev/null
chk "gate1 payload has no H1" "$(payload "$W/g1.html" | grep -c '^# ')" "0"
chk "gate1 payload has the sentinel Plan heading" \
  "$(payload "$W/g1.html" | grep -c '^## Plan')" "1"
chk "gate1 payload has the pending callout" \
  "$(payload "$W/g1.html" | grep -c '^> \[!PENDING\]')" "1"

"$S/render.sh" "$W/s.md" "$W/p.md" -o "$W/g2.html" >/dev/null
chk "gate2 payload has no H1" "$(payload "$W/g2.html" | grep -c '^# ')" "0"
chk "gate2 payload has no pending callout" \
  "$(payload "$W/g2.html" | grep -c '^> \[!PENDING\]')" "0"
chk "gate2 payload keeps the task" \
  "$(payload "$W/g2.html" | grep -c '^### Task 1: A')" "1"

# A plan with no H1 whose first fence contains a hash comment.
printf '### Task 1: A\n\n```bash\n# Install deps first\nnpm ci\n```\n' > "$W/nh1.md"
"$S/render.sh" "$W/s.md" "$W/nh1.md" -o "$W/nh1.html" >/dev/null
chk "fenced hash comment survives" \
  "$(payload "$W/nh1.html" | grep -c '^# Install deps first$')" "1"

# Leading blank line, BOM, and YAML front matter must not defeat the H1 strip.
printf '\n\n# Plan Blank\n\n### Task 1: A\n' > "$W/blank.md"
"$S/render.sh" "$W/s.md" "$W/blank.md" -o "$W/blank.html" >/dev/null
chk "leading blank line: H1 still stripped" "$(payload "$W/blank.html" | grep -c '^# ')" "0"

printf '\xef\xbb\xbf# Plan Bom\n\n### Task 1: A\n' > "$W/bom.md"
"$S/render.sh" "$W/s.md" "$W/bom.md" -o "$W/bom.html" >/dev/null
chk "BOM: H1 still stripped" "$(payload "$W/bom.html" | grep -c '^# ')" "0"

printf -- '---\ntitle: X\n---\n# Plan Yaml\n\n### Task 1: A\n' > "$W/yaml.md"
"$S/render.sh" "$W/s.md" "$W/yaml.md" -o "$W/yaml.html" >/dev/null
chk "front matter dropped, H1 stripped" "$(payload "$W/yaml.html" | grep -c '^# ')" "0"
chk "front matter body retained" "$(payload "$W/yaml.html" | grep -c '^### Task 1: A')" "1"

# A leading thematic break is NOT front matter. Consuming to EOF would delete
# the document while still emitting a correct title and exit 0.
printf -- '---\n\n# Real Title\n\n## Why\n\nbody\n' > "$W/rule.md"
"$S/render.sh" "$W/rule.md" -o "$W/rule.html" >/dev/null
chk "leading thematic break passes through" \
  "$(payload "$W/rule.html" | grep -c '^## Why$')" "1"

chk "missing output dir is created" \
  "$("$S/render.sh" "$W/s.md" -o "$W/deep/nested/out.html" >/dev/null 2>&1; [ -f "$W/deep/nested/out.html" ] && echo yes || echo no)" "yes"

echo "== render.sh: directory and CRLF source rejection (defect round) =="
# A directory passes -r on most systems, so a naive readability check lets it
# through: strip_bom's sed then runs against the directory, prints zero bytes
# with no error, and the render reports success on an empty section. -o and
# leaves-no-output-file are checked directly rather than via payload(), since
# a zero-byte section is exactly the failure mode under test -- a payload()
# count of "0" here would prove nothing either way.
mkdir -p "$W/specdir" "$W/plandir"
# A minimal stand-in template: only enough to clear the TPL/CRLF preconditions
# that run ahead of the plan check, so the directory-as-plan case is actually
# exercised instead of being masked by "cannot read template" (template.html
# does not exist yet -- see Task 7). It need not carry any placeholders: the
# plan check runs before the placeholder-presence loop.
printf 'minimal placeholder-free stand-in template\n' > "$W/notpl.html"

"$S/render.sh" "$W/specdir" -o "$W/dirspec_out.html" >/dev/null 2>"$W/err.txt"
chk "directory as spec exits 1" "$?" "1"
grep -q 'cannot read spec' "$W/err.txt" && ok "  names the spec as the problem" \
  || no "  names the spec as the problem" "$(cat "$W/err.txt")"
[ -f "$W/dirspec_out.html" ] && no "  directory-as-spec leaves no output file" "file exists" \
  || ok "  directory-as-spec leaves no output file"

"$S/render.sh" "$W/spec.md" "$W/plandir" -o "$W/dirplan_out.html" -t "$W/notpl.html" >/dev/null 2>"$W/err.txt"
chk "directory as plan exits 1" "$?" "1"
grep -q 'cannot read plan' "$W/err.txt" && ok "  names the plan as the problem" \
  || no "  names the plan as the problem" "$(cat "$W/err.txt")"
[ -f "$W/dirplan_out.html" ] && no "  directory-as-plan leaves no output file" "file exists" \
  || ok "  directory-as-plan leaves no output file"

# A CRLF spec combined with a leading blank line: strip_h1's blank-line check
# does not match a CRLF blank line (the \r is not in [ \t]), so that line is
# taken as the first content line and the real H1 below it is never examined.
# render.sh now rejects any CRLF spec/plan outright, mirroring the template's
# existing CRLF guard, rather than trying to strip a body it cannot parse
# correctly.
printf '\r\n# Title\r\nbody\r\n' > "$W/crlf_spec.md"
"$S/render.sh" "$W/crlf_spec.md" -o "$W/crlfspec_out.html" >/dev/null 2>"$W/err.txt"
chk "CRLF spec (with leading blank line) exits 1" "$?" "1"
grep -qi 'crlf' "$W/err.txt" && ok "  names CRLF as the cause" \
  || no "  names CRLF as the cause" "$(cat "$W/err.txt")"
[ -f "$W/crlfspec_out.html" ] && no "  CRLF spec leaves no output file" "file exists" \
  || ok "  CRLF spec leaves no output file"

echo "== diagnostics, provenance, injection =="
printf '# Hostile | Title & <redesign> "x" \\ y\n\n## Why\n\nbody\n' > "$W/host.md"
"$S/render.sh" "$W/host.md" -o "$W/host.html" >/dev/null
title=$(python3 - "$W/host.html" <<'PY'
import sys, re, base64
h = open(sys.argv[1], encoding='utf-8').read()
print(base64.b64decode(re.search(r'data-title="([^"]*)"', h).group(1)).decode('utf-8'))
PY
)
chk "hostile title round-trips" "$title" 'Hostile | Title & <redesign> "x" \ y'
chk "hostile title never appears as raw markup" \
  "$(grep -c '<redesign>' "$W/host.html")" "0"

printf '## No H1 Here\n\nbody\n' > "$W/noh1.md"
"$S/render.sh" "$W/noh1.md" -o "$W/noh1.html" >/dev/null
title=$(python3 - "$W/noh1.html" <<'PY'
import sys, re, base64
h = open(sys.argv[1], encoding='utf-8').read()
print(base64.b64decode(re.search(r'data-title="([^"]*)"', h).group(1)).decode('utf-8'))
PY
)
chk "title falls back to the basename" "$title" "noh1"

chk "no placeholder survives" \
  "$(grep -cE '__(TITLE_B64|SOURCES_B64|GENERATED|DIAG_B64|PLANSTATE|VENDOR_JS|BRIEF_B64)__' "$W/g1.html")" "0"
tb=$(wc -c < "$S/template.html"); ob=$(wc -c < "$W/g1.html")
[ "$ob" -gt "$tb" ] && ok "output larger than template" || no "output larger than template" "$ob <= $tb"

chk "vendor injected exactly once" \
  "$(grep -c 'marked v12\.0\.2' "$W/g1.html")" "1"

chk "plan-state attached" \
  "$(grep -c 'data-plan-state="attached"' "$W/g2.html")" "1"
chk "plan-state pending" \
  "$(grep -c 'data-plan-state="pending"' "$W/g1.html")" "1"

# Provenance: identical bytes give identical digests, changed bytes differ.
# Guarded: a missing/empty fixture, or a data-sources attribute that failed to
# extract from either side, must fail loudly rather than let two coincidentally
# equal empty extractions read as "identical" (a real failure, but for the
# wrong reason) or, worse, let one built and one unbuilt fixture read as
# "different" (a false pass).
"$S/render.sh" "$W/s.md" -o "$W/d1.html" >/dev/null
printf '# Spec Title\n\n## Design\n\nbody changed\n' > "$W/s2.md"
"$S/render.sh" "$W/s2.md" -o "$W/d2.html" >/dev/null
if [ ! -s "$W/d1.html" ] || [ ! -s "$W/d2.html" ]; then
  no "provenance changes with source bytes" "fixture not built: d1.html or d2.html missing/empty"
else
  d1=$(grep -o 'data-sources="[^"]*"' "$W/d1.html")
  d2=$(grep -o 'data-sources="[^"]*"' "$W/d2.html")
  if [ -z "$d1" ] || [ -z "$d2" ]; then
    no "provenance changes with source bytes" "data-sources attribute not found in d1.html or d2.html"
  elif [ "$d1" != "$d2" ]; then
    ok "provenance changes with source bytes"
  else
    no "provenance changes with source bytes" "identical"
  fi
fi

# Idempotent apart from the generation timestamp. Guarded: a missing or
# zero-byte fixture must fail loudly rather than let two empty `sed` streams
# (one per unbuilt file) diff as equal and read as a real idempotency proof.
"$S/render.sh" "$W/s.md" -o "$W/i1.html" >/dev/null
"$S/render.sh" "$W/s.md" -o "$W/i2.html" >/dev/null
if [ ! -s "$W/i1.html" ] || [ ! -s "$W/i2.html" ]; then
  no "renders are idempotent apart from the timestamp" "fixture not built: i1.html or i2.html missing/empty"
elif diff <(sed 's/data-generated="[^"]*"/X/' "$W/i1.html") \
        <(sed 's/data-generated="[^"]*"/X/' "$W/i2.html") >/dev/null; then
  ok "renders are idempotent apart from the timestamp"
else
  no "renders are idempotent apart from the timestamp" "differ"
fi

printf '# T\n\n## D\n\n```bash\necho hi\n' > "$W/openf.md"
"$S/render.sh" "$W/openf.md" -o "$W/openf.html" 2>"$W/warn.txt" >/dev/null
grep -q 'Unterminated code fence' "$W/warn.txt" && ok "unterminated fence warns on stderr" \
  || no "unterminated fence warns on stderr" "$(cat "$W/warn.txt")"
"$S/render.sh" "$W/s.md" -o "$W/clean.html" 2>"$W/warn2.txt" >/dev/null
chk "clean document warns nothing" "$(wc -c < "$W/warn2.txt" | tr -d ' ')" "0"

echo "== title derivation agrees with strip_h1 on which line is the H1 =="
# Guarded like payload() above: a missing or empty output file must fail every
# assertion below outright, not be handed to python3 and read as a coincidental
# empty title that the expected (always non-empty) value just happens not to
# match. title_of() makes that failure explicit instead of relying on python's
# traceback-on-missing-file leaving $title empty by accident.
title_of() {
  if [ -s "$1" ]; then
    python3 - "$1" <<'PY'
import sys, re, base64
h = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'data-title="([^"]*)"', h, re.S)
print(base64.b64decode(re.sub(r'\s', '', m.group(1))).decode('utf-8') if m else '__NO_DATA_TITLE_ATTRIBUTE__')
PY
  else
    echo "__FIXTURE_NOT_BUILT__"
  fi
}

# The regression this whole section guards against: a spec with no real H1
# whose first (and only) fenced code block contains a line starting with "# ".
# A fence-unaware "first /^# / anywhere" title scan lifts that line out of the
# fence; the correct behaviour is to fall back to the basename, exactly as a
# document with no "# " line at all would.
printf '## No H1 Here\n\nintro.\n\n```bash\n# comment inside fence\necho hi\n```\n\nmore text\n' > "$W/titlefence.md"
"$S/render.sh" "$W/titlefence.md" -o "$W/titlefence.html" >/dev/null
chk "title ignores a hash comment inside a fence when there is no H1" \
  "$(title_of "$W/titlefence.html")" "titlefence"

printf -- '---\ntitle: FrontMatterValue\n---\n# Real Title\n\nbody\n' > "$W/fmtitle.md"
"$S/render.sh" "$W/fmtitle.md" -o "$W/fmtitle.html" >/dev/null
chk "title after front matter is the H1, not the front-matter value" \
  "$(title_of "$W/fmtitle.html")" "Real Title"

printf '\n\n\n# Blank Then Title\n\nbody\n' > "$W/blanktitle.md"
"$S/render.sh" "$W/blanktitle.md" -o "$W/blanktitle.html" >/dev/null
chk "title survives leading blank lines before the H1" \
  "$(title_of "$W/blanktitle.html")" "Blank Then Title"

echo "== template placeholders =="
for ph in __TITLE_B64__ __SOURCES_B64__ __GENERATED__ __DIAG_B64__ __PLANSTATE__ __VENDOR_JS__ __BRIEF_B64__; do
  chk "$ph appears exactly once" "$(grep -c "$ph" "$S/template.html")" "1"
done
chk "__VENDOR_JS__ alone on its line" "$(grep -c '^__VENDOR_JS__$' "$S/template.html")" "1"
chk "__BRIEF_B64__ alone on its line"  "$(grep -c '^__BRIEF_B64__$'  "$S/template.html")" "1"

# A template with a placeholder deleted must abort, not render blank.
grep -v '^__VENDOR_JS__$' "$S/template.html" | grep -v '__VENDOR_JS__' > "$W/tpl-missing.html"
"$S/render.sh" "$W/s.md" -t "$W/tpl-missing.html" -o "$W/miss.html" >/dev/null 2>"$W/err.txt"
chk "missing placeholder aborts" "$?" "1"
grep -q 'missing __VENDOR_JS__' "$W/err.txt" && ok "  names the missing placeholder" \
  || no "  names the missing placeholder" "$(cat "$W/err.txt")"
[ -f "$W/miss.html" ] && no "  leaves no output file" "exists" || ok "  leaves no output file"

echo "== template JS: decode and masthead =="
chk "decodeB64 helper present" "$(grep -c 'function decodeB64' "$S/template.html")" "1"
chk "title written with textContent" \
  "$(grep -c 'briefTitle").textContent = title' "$S/template.html")" "1"
chk "theme persisted to localStorage" \
  "$(grep -c "localStorage.setItem(\"brief-theme\"" "$S/template.html")" "1"

echo "== large document does not trigger a SIGPIPE abort (pipe-buffer regression) =="
# Every fixture above this line is small enough to stay under any plausible
# OS pipe-buffer size, which is exactly why this suite passed while
# first_content_line could still SIGPIPE render.sh to death on this project's
# own ~48KB spec. 2400 real (non-repeating) body lines comfortably clears
# even a generous 64KB buffer, so the assertion stays meaningful even if
# buffer sizes differ across platforms.
{
  printf '# Large Spec Title\n\n## Section\n\n'
  i=1
  while [ "$i" -le 2400 ]; do
    printf 'This is body line %d of a synthetic large spec used to exceed the OS pipe buffer.\n' "$i"
    i=$((i + 1))
  done
} > "$W/large.md"
large_bytes=$(wc -c < "$W/large.md" | tr -d ' ')
[ "$large_bytes" -gt 100000 ] && ok "synthetic large spec exceeds 100KB (test stays meaningful across platforms)" \
  || no "synthetic large spec exceeds 100KB (test stays meaningful across platforms)" "only ${large_bytes}B"
"$S/render.sh" "$W/large.md" -o "$W/large.html" >/dev/null 2>"$W/large_err.txt"
rc=$?
chk "large spec (${large_bytes}B) renders instead of SIGPIPE-aborting" "$rc" "0"
if [ "$rc" -eq 0 ] && [ -s "$W/large.html" ]; then
  chk "large spec output has no unsubstituted placeholder" \
    "$(grep -cE '__(TITLE_B64|SOURCES_B64|GENERATED|DIAG_B64|PLANSTATE|VENDOR_JS|BRIEF_B64)__' "$W/large.html")" "0"
  chk "large spec title is correct, not lost to a truncated render" \
    "$(payload "$W/large.html" | grep -c '^## Section$')" "1"
  chk "large spec payload keeps its very last body line intact" \
    "$(payload "$W/large.html" | grep -c '^This is body line 2400 of')" "1"
else
  no "large spec output has no unsubstituted placeholder" "render failed: $(cat "$W/large_err.txt")"
  no "large spec title is correct, not lost to a truncated render" "render failed: $(cat "$W/large_err.txt")"
  no "large spec payload keeps its very last body line intact" "render failed: $(cat "$W/large_err.txt")"
fi

echo "== renders this repository's own real spec and plan (the regression that mattered) =="
# Every fixture above is synthetic. These are the actual documents render.sh
# exists to render, present in every checkout — using them here is what would
# have caught the SIGPIPE regression immediately instead of shipping it.
REALSPEC="$R/docs/specs/2026-07-27-visual-change-briefs-design.md"
REALPLAN="$R/docs/plans/2026-07-30-visual-change-briefs.md"
if [ -s "$REALSPEC" ] && [ -s "$REALPLAN" ]; then
  "$S/render.sh" "$REALSPEC" "$REALPLAN" -o "$W/real.html" >/dev/null 2>"$W/real_err.txt"
  rc=$?
  chk "real spec+plan render exits 0 instead of SIGPIPE (141)" "$rc" "0"
  if [ "$rc" -eq 0 ] && [ -s "$W/real.html" ]; then
    # The sentinel is "## Plan" plus a trailing U+2060 WORD JOINER on its own
    # line. A plain '^## Plan' match is not enough: the real plan document
    # has its own "## Plan" and "## Plan blocks" headings, so only the
    # byte-exact sentinel line proves the parse structure survived.
    chk "real spec+plan payload decodes with the sentinel present" \
      "$(payload "$W/real.html" | grep -c $'^## Plan\xe2\x81\xa0$')" "1"
  else
    no "real spec+plan payload decodes with the sentinel present" "render failed: $(cat "$W/real_err.txt")"
  fi
else
  no "real spec+plan render exits 0 instead of SIGPIPE (141)" \
    "fixture not present: $REALSPEC or $REALPLAN missing/empty"
  no "real spec+plan payload decodes with the sentinel present" "fixture not present"
fi

echo "== template JS: failure containment (one bad attribute or a throwing localStorage must not blank the page) =="
# These are static proxies for a runtime fix -- whether the page actually
# degrades gracefully cannot be expressed as a grep (there is no JS engine
# in this suite), so it was verified separately in a real browser. Each
# assertion below is tied to a specific line of the fix, not to loose
# vocabulary ("does the file mention guard somewhere"), because this suite
# has already had five separate false-passing-assertion incidents -- most
# recently a '^## Plan' check that matched three unrelated headings instead
# of the one byte-exact sentinel line.

chk "guard() containment helper is defined" \
  "$(grep -c 'function guard(label, fn)' "$S/template.html")" "1"
chk "guard() catches and reports rather than rethrowing" \
  "$(grep -c 'try { fn(); } catch (e) { warn(label, e); }' "$S/template.html")" "1"
chk "safeDecode() helper is defined" \
  "$(grep -c 'function safeDecode(b64, label)' "$S/template.html")" "1"
chk "safeDecode() catches and reports rather than rethrowing" \
  "$(grep -c 'catch (e) { warn(label, e); return "";' "$S/template.html")" "1"

chk "title decode now routes through safeDecode" \
  "$(grep -c 'safeDecode(document.body.dataset.title,' "$S/template.html")" "1"
chk "title decode no longer calls decodeB64 directly and unguarded" \
  "$(grep -c 'decodeB64(document.body.dataset.title)' "$S/template.html")" "0"
chk "sources decode now routes through safeDecode" \
  "$(grep -c 'safeDecode(document.body.dataset.sources,' "$S/template.html")" "1"
chk "sources decode no longer calls decodeB64 directly and unguarded" \
  "$(grep -c 'decodeB64(document.body.dataset.sources)' "$S/template.html")" "0"

chk "stored theme value is validated against the known set before use" \
  "$(grep -c 'THEMES.indexOf(stored) !== -1' "$S/template.html")" "1"
chk "reading the stored theme preference is wrapped in guard()" \
  "$(grep -c 'guard("theme: read stored preference"' "$S/template.html")" "1"
chk "persisting the theme choice is wrapped in guard() (setItem can throw)" \
  "$(grep -c 'guard("theme: persist preference"' "$S/template.html")" "1"
chk "applyTheme() still runs immediately after the guarded persist attempt" \
  "$(grep -A2 'localStorage.setItem("brief-theme", pref);' "$S/template.html" | grep -c 'applyTheme();')" "1"

chk "payload decode failure is reported to the console like the other sections" \
  "$(grep -c 'warn("payload decode", e)' "$S/template.html")" "1"

echo "== template JS: guard() containment (floor + specific labels, not a pinned count) =="
# A pinned exact count blocks every future task from adding a new guarded
# section without also bumping this one number -- Task 9's implementer left
# their inertness block unguarded partly because of exactly this pin. Assert
# containment instead: each section known to need guarding today is guarded
# by name, and the total never drops below today's floor. A later task that
# adds more guarded sections raises the floor in its own commit; it does not
# need to touch this one.
for label in \
  'guard("theme: read stored preference"' \
  'guard("theme: wire controls"' \
  'guard("theme: persist preference"' \
  'guard("theme: attach system-preference listener"' \
  'guard("theme: apply initial"' \
  'guard("masthead: apply title"' \
  'guard("masthead: stamps"' \
; do
  chk "guarded: $label" "$(grep -cF "$label" "$S/template.html")" "1"
done
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 7 ] && ok "at least 7 top-level sections guarded (floor, not a ceiling)" \
  || no "at least 7 top-level sections guarded (floor, not a ceiling)" "$n"

echo "== template JS: inertness =="
chk "backslashes normalised before the // check" \
  "$(grep -c 'replace(/\\\\/g, "/")' "$S/template.html")" "1"
chk "entity decoding via detached textarea" \
  "$(grep -c 'function decodeEntities' "$S/template.html")" "1"
chk "scheme allowlist is http/https/mailto only" \
  "$(grep -cF 'https?|mailto' "$S/template.html")" "1"
chk "marked.use absence refuses to render" \
  "$(grep -c 'Renderer unavailable' "$S/template.html")" "1"
chk "remote images become chips" "$(grep -c 'img-chip' "$S/template.html")" "3"

echo "== template JS: safeHref check and embed now use the same value (fix) =="
# safeHref used to validate decodeEntities(raw) but the link renderer embedded
# esc(href) -- the original, undecoded string. The check and the embed
# operated on different values; inert only because decode_once(esc(raw)) ===
# raw is an algebraic identity for the untampered case, not because the
# check and the embed agreed. Repro (verified separately in a real browser):
#   [x](&amp;#106;avascript:window.__PWNED__='x')
# Fix: normalizeHref() produces one normalized value; safeHref() validates it
# and the renderer embeds that same value, not the raw input.
chk "normalizeHref helper exists and does the normalising, separately from the boolean check" \
  "$(grep -c 'function normalizeHref(raw)' "$S/template.html")" "1"
chk "safeHref now validates an already-normalized value, not a raw one" \
  "$(grep -c 'function safeHref(h)' "$S/template.html")" "1"
chk "link renderer computes the normalized value once, before validating it" \
  "$(grep -c 'var h = normalizeHref(href || "");' "$S/template.html")" "1"
chk "link renderer no longer embeds the raw undecoded href (image chip + rejected-link text still legitimately do)" \
  "$(grep -c -- '+ esc(href) +' "$S/template.html")" "2"
chk "anchor href is built from esc(h) -- the same normalized value safeHref validated" \
  "$(grep -c -- '+ esc(h) +' "$S/template.html")" "1"

echo "== template JS: inertness block is now itself contained (fix) =="
# Task 9's block had no guard(): safe only while it was the IIFE's last
# statement. Task 10 appends code after it, so an uncaught throw here would
# have silently killed everything appended after it and left the page blank
# with no banner at all -- exactly the failure this project exists to
# prevent. Runtime behaviour (does a throwing marked.use actually surface the
# banner?) cannot be expressed as a grep and was verified separately in a
# real browser; these are static proxies tied to specific lines of the fix.
chk "guarded: inertness: render payload" \
  "$(grep -cF 'guard("inertness: render payload"' "$S/template.html")" "1"
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 8 ] && ok "at least 8 top-level sections guarded (floor raised by this fix)" \
  || no "at least 8 top-level sections guarded (floor raised by this fix)" "$n"
chk "rendererUnavailable is defined once, called from both the missing- and throwing-marked.use paths" \
  "$(grep -c 'rendererUnavailable(' "$S/template.html")" "3"
chk "a throwing marked.use is caught and reported like every other guarded section" \
  "$(grep -c 'warn("inertness: render payload", e)' "$S/template.html")" "1"

echo "== template JS: structural integrity =="
chk "sentinel constant present" "$(grep -cF 'PLAN_MARK = "\u2060"' "$S/template.html")" "1"
chk "content-lost banner present" \
  "$(grep -c 'Content lost during rendering' "$S/template.html")" "1"
chk "render.sh warnings surface as banners" \
  "$(grep -c 'Source problem' "$S/template.html")" "1"
chk "no source-side heading count remains" \
  "$(grep -c 'data-headings' "$S/template.html")" "0"

echo "== template JS: callouts, badges, progress =="
chk "PENDING alert mapped" "$(grep -c 'PENDING:"pending"' "$S/template.html")" "1"
chk "pending label text" "$(grep -c 'Plan not yet written' "$S/template.html")" "1"
chk "data-toc capture present" "$(grep -c 'h.dataset.toc =' "$S/template.html")" "1"
chk "mermaid fences become boxes" \
  "$(grep -c 'code.language-mermaid' "$S/template.html")" "1"
# The line above greps the INPUT selector. Task 13 consumes the output --
# ".mermaid-block" and its data-src -- so renaming the class or moving off
# dataset.src would leave this suite green while Task 13 got an empty
# NodeList. Anchor on the whole assignment: Task 12 builds a mermaid-block
# with a data-src of its own for the DAG, so a count on either bare string
# would break the moment that lands.
chk "mermaid box carries the fence text" \
  "$(grep -c 'box.dataset.src = code.textContent' "$S/template.html")" "1"
# "before mutation" is the whole point of the capture -- badges and progress
# rewrite heading contents, so a capture that runs after them yields index
# entries reading "Task 1: Render scriptstatic-verifiable". Presence alone
# cannot see that; assert the source order the correctness depends on.
toc_ln=$(grep -n 'h.dataset.toc =' "$S/template.html" | head -1 | cut -d: -f1)
badge_ln=$(grep -n 'guard("decorate: walk badges"' "$S/template.html" | head -1 | cut -d: -f1)
prog_ln=$(grep -n 'guard("decorate: task progress"' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$toc_ln" ] && [ -n "$badge_ln" ] && [ -n "$prog_ln" ] \
   && [ "$toc_ln" -lt "$badge_ln" ] && [ "$toc_ln" -lt "$prog_ln" ]; then
  ok "data-toc capture precedes both badge and progress mutation in source order"
else
  no "data-toc capture precedes both badge and progress mutation in source order" \
     "toc=[${toc_ln:-missing}] badges=[${badge_ln:-missing}] progress=[${prog_ln:-missing}]"
fi
# Containment for the five sections this task adds, asserted by label like the
# floor+labels block above. The >=8 floor alone cannot catch one of these being
# unwrapped later: 12 of 13 still clears 8.
for label in \
  'guard("decorate: mermaid fences"' \
  'guard("decorate: callouts"' \
  'guard("decorate: heading toc text"' \
  'guard("decorate: walk badges"' \
  'guard("decorate: task progress"' \
; do
  chk "guarded: $label" "$(grep -cF "$label" "$S/template.html")" "1"
done
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 13 ] && ok "at least 13 top-level sections guarded (floor raised by this task)" \
  || no "at least 13 top-level sections guarded (floor raised by this task)" "$n"
# The one deliberate exception to that doctrine. sectionNodes is a helper the
# guarded sections and Task 12 call; wrapping it in guard() would scope the
# declaration to the callback and its callers would fail with a ReferenceError
# reported under someone else's label.
# Anchored to indent 2 on purpose. An unanchored 'function sectionNodes' count
# stays at 1 when the declaration is wrapped in a guard() -- the exact failure
# this label names -- because the declaration is still there, just at indent 4,
# the way decodeEntities sits inside the inertness guard. The anchor is what
# makes the assertion test its own claim.
chk "sectionNodes stays a declaration at IIFE scope, not inside a guard()" \
  "$(grep -c '^  function sectionNodes' "$S/template.html")" "1"
chk "the fill bar floors its percentage rather than rounding 199/200 to 100%" \
  "$(grep -c 'Math.floor(done / boxes.length \* 100)' "$S/template.html")" "1"
chk "callout marker is read from the blockquote's own first child, not any descendant p" \
  "$(grep -c 'var first = bq.firstElementChild;' "$S/template.html")" "1"
chk "descendant-scoped querySelector(\"p\") is gone from the callout walk" \
  "$(grep -c 'bq.querySelector("p")' "$S/template.html")" "0"

echo "== template JS: dependency graph =="
# Label says only what the grep can see: the anchor is present in the regex
# text. The paragraph half of the old label -- "to paragraph start" -- is
# carried by "only P elements are scanned for a declaration" further down; this
# line cannot see it, and promising it here is how an assertion outlives the
# behaviour it was meant to pin.
chk "the declaration regex is anchored in its literal text (text pin only)" \
  "$(grep -c '\^Depends on:' "$S/template.html")" "1"
# Label says only what the grep can actually see. "none suppresses edges"
# promised behaviour a presence grep cannot check; the suppression itself is
# covered by the DOM walk, not by this line.
chk "the none-suppression regex literal is present (text pin only)" \
  "$(grep -c '\^none' "$S/template.html")" "1"
# Anchored to indent 2, unlike the plan's original unanchored form and for the
# reason the sectionNodes assertion above spells out: 'function planTasks'
# still counts 1 when the declaration is wrapped in a guard(), which is the
# regression the label exists to forbid. (Task 15 replaces planTasks with
# planRegionHeadings and must retarget this line in its anchored form.)
chk "graph scoped by plan region" \
  "$(grep -c '^  function planTasks' "$S/template.html")" "1"
chk "unknown edge targets dropped" \
  "$(grep -c 'known\[e\[0\]\] && known\[e\[1\]\]' "$S/template.html")" "1"
# Same anchor, same reason: buildDag is a helper the guarded sections call, so
# a guard() wrapper scopes its declaration to that callback and the caller dies
# with "buildDag is not defined", reported under someone else's label.
chk "buildDag stays a declaration at IIFE scope, not inside a guard()" \
  "$(grep -c '^  function buildDag' "$S/template.html")" "1"
# The one binding that deliberately does NOT live inside its guard. Task 15
# adds a sibling "No tasks found" banner statement that reads `tasks`; a
# declaration hoisted into a guard callback is function-scoped to it and
# invisible there. Indent 2 IS the assertion -- moving it inside the callback
# reindents it to 4 and this fails, which is exactly the claim in the label.
chk "tasks is declared at IIFE scope, not inside a guard callback" \
  "$(grep -c '^  var tasks = \[\];' "$S/template.html")" "1"
chk "the collect guard assigns that outer binding rather than declaring a fresh local" \
  "$(grep -c '^    tasks = plan' "$S/template.html")" "1"
# The anchored regex alone does not make the scan paragraph-scoped: without
# this filter every node in the section is searched, and the string is
# harvested out of code fences and list items alike -- a plan step reading
# 'add `Depends on: Task 3` to the template' fabricated a real edge.
chk "only P elements are scanned for a declaration" \
  "$(grep -c 'if (nodes\[i\].tagName !== "P") continue;' "$S/template.html")" "1"
# Containment for the two sections this task adds, by label, per the doctrine.
for label in \
  'guard("dag: collect plan tasks"' \
  'guard("dag: build and insert graph"' \
; do
  chk "guarded: $label" "$(grep -cF "$label" "$S/template.html")" "1"
done
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 15 ] && ok "at least 15 top-level sections guarded (floor raised by this task)" \
  || no "at least 15 top-level sections guarded (floor raised by this task)" "$n"
# planTasks() reads planH2, a var assigned by the structural-integrity block
# above. The declaration hoists; the CALL does not. A collect guard placed
# before that assignment sees undefined, returns [], and the graph disappears
# with no error on the page and none in the console either. Presence greps
# cannot see that; assert the source order the correctness depends on.
planh2_ln=$(grep -n '^  var planH2 = ' "$S/template.html" | head -1 | cut -d: -f1)
collect_ln=$(grep -n 'guard("dag: collect plan tasks"' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$planh2_ln" ] && [ -n "$collect_ln" ] && [ "$planh2_ln" -lt "$collect_ln" ]; then
  ok "the plan-region scan runs after planH2 is assigned"
else
  no "the plan-region scan runs after planH2 is assigned" \
     "planH2=[${planh2_ln:-missing}] collect=[${collect_ln:-missing}]"
fi

echo "== template JS: dependency graph — derivation defects =="
# A1. dm[1].match(/\d+/g) read every number left in the declaration as a task
# id. "Depends on: Task 1 (see section 4.2 of the spec)" emitted the real edge
# plus phantom 4-> and 2->, and on a plan that HAS a task 4 the phantom reverses
# the real 3->4 and draws a cycle the source never declared. known[] only drops
# numbers larger than the task count, so it protects two-task plans and nothing
# else. Each of these four lines is one half of the replacement; all four are
# needed for the tokenised form to be the tokenised form.
chk "the loose digit harvest is gone" \
  "$(grep -cF 'dm[1].match(/\d+/g)' "$S/template.html")" "0"
chk "parentheticals are stripped before the split" \
  "$(grep -cF 'replace(/\([^)]*\)/g, " ")' "$S/template.html")" "1"
chk "the declaration is split into tokens on comma/semicolon/and/&/+/dash" \
  "$(grep -cF 'split(/\s*(?:,|;|\band\b|&|\+|[–—]|\s-\s)\s*/i)' "$S/template.html")" "1"
# The dash separators and the range pre-pass are ONE change. Dashes alone turn
# "Tasks 1-3" into ["Tasks 1", "3"] -- edges from 1 and 3 with 2 silently
# missing, which trades honest silence for a quietly incomplete graph. Assert
# the pairing rather than each half, so neither can land without the other.
dash_split=$(grep -cF '|[–—]|\s-\s' "$S/template.html")
range_call=$(grep -cF 'expandRanges(dm[1].replace' "$S/template.html")
if [ "$dash_split" = "1" ] && [ "$range_call" = "1" ]; then
  ok "dash separators and the range pre-pass landed together, never one without the other"
else
  no "dash separators and the range pre-pass landed together, never one without the other" \
     "dash-in-split=[$dash_split] expandRanges-call=[$range_call]"
fi
# The composed call is the ordering: parentheticals stripped, THEN ranges
# expanded, and .split chained on that result. Expanding after the split is
# too late -- the range is already two tokens by then.
chk "ranges are expanded after parentheticals are stripped and before the split" \
  "$(grep -cF 'expandRanges(dm[1].replace(/\([^)]*\)/g, " "))' "$S/template.html")" "1"
chk "only plain integers are treated as range endpoints, never a dotted id's tail" \
  "$(grep -cF '/(^|[^\d.])(\d+)\s*[–—-]\s*(\d+)(?![\d.])/g' "$S/template.html")" "1"
chk "an absurd or descending span is left alone rather than expanded" \
  "$(grep -cF 'if (hi < lo || hi - lo > 64) return all;' "$S/template.html")" "1"
chk "a token earns an edge only if the whole token is a task reference" \
  "$(grep -cF '/^\s*(?:Tasks?\s*)?#?(\d+(?:\.\d+)*)\.?\s*$/i' "$S/template.html")" "1"
chk "self-edges are dropped" \
  "$(grep -cF 'if (d !== id) edges.push([d, id]);' "$S/template.html")" "1"

# A2. Two headings on one id render as ONE mermaid node with the last label --
# verified against the vendored 10.9.1 -- so a real task is deleted silently and
# its edges misroute onto the survivor. Root cause is the id shape: "." reads as
# the title separator, so 2.1 and 2.2 both collapse onto T2, and "Task 03" never
# matches a "Depends on: Task 3" reference.
chk "the heading id captures a dotted sub-number" \
  "$(grep -cF '/^Task\s+(\d+(?:\.\d+)*)\s*[:.—-]?\s*(.*)$/i' "$S/template.html")" "1"
chk "every id segment is normalised through parseInt, killing zero-padding" \
  "$(grep -cF 'String(parseInt(seg, 10))' "$S/template.html")" "1"
chk "the mermaid node name is derived from the id, dots to underscores" \
  "$(grep -cF 'function nodeName(id){ return "T" + id.replace(/\./g, "_"); }' "$S/template.html")" "1"
# The rename is only real if nothing still concatenates a bare id into a node
# name; a leftover "T" + e[0] emits T2.1, which is not a legal node name.
chk "no bare T-plus-id node name is left behind" \
  "$(grep -cF '"  T" + e[0]' "$S/template.html")" "0"
chk "colliding ids suppress the graph instead of emitting a silently wrong one" \
  "$(grep -cF 'if (dup) return { src: null, dup: dup };' "$S/template.html")" "1"

# A3. The negative caption asserted a fact about the SOURCE while knowing only a
# fact about the PARSE. A plan declaring "- **Depends on:** Task 1" as a list
# item, or in a table cell, is correctly skipped by the P-only scan -- and the
# page then told the reader those tasks were independent.
chk "the old source-level claim is gone" \
  "$(grep -c 'tasks are independent' "$S/template.html")" "0"
chk "the negative caption describes what was recognised, not what the plan says" \
  "$(grep -c 'no Depends on: declarations were recognised' "$S/template.html")" "1"
# A suppressed graph is the most important thing this feature ever says. As a
# .dag-caption with no diagram above it, it rendered as a faint 12px mono line
# tucked under the Plan heading by a negative margin decorating nothing.
chk "a suppressed graph is announced as a banner, not as a caption" \
  "$(grep -cF 'banner("Dependency graph suppressed"' "$S/template.html")" "1"
# The caption is now unconditional -- the suppression path returns before it is
# built. A ternary here would mean the caption still carries that message.
chk "the caption no longer branches on whether a graph exists" \
  "$(grep -cF 'cap.textContent = dag.edges' "$S/template.html")" "1"
sup_ln=$(grep -n 'banner("Dependency graph suppressed"' "$S/template.html" | head -1 | cut -d: -f1)
cap_ln=$(grep -n 'cap.className = "dag-caption";' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$sup_ln" ] && [ -n "$cap_ln" ] && [ "$sup_ln" -lt "$cap_ln" ]; then
  ok "the suppression path returns before any caption element is built"
else
  no "the suppression path returns before any caption element is built" \
     "banner=[${sup_ln:-missing}] caption=[${cap_ln:-missing}]"
fi

# A4. A trailing h2 terminates sectionNodes, but trailing content with no
# heading does not: the last task's section runs to EOF, so a closing paragraph
# after a "---" rule was read as that task's declaration.
chk "an HR stops the declaration scan" \
  "$(grep -cF 'if (nodes[i].tagName === "HR") break;' "$S/template.html")" "1"

# A5/A6, and the two behaviours the block never covered at all.
chk "the walk tag is matched at the end of the heading, not as a substring" \
  "$(grep -cF '/\s*[—–-]\s*browser-walk-only\s*$/.test(h.textContent)' "$S/template.html")" "1"
chk "duplicate declarations collapse to one arrow" \
  "$(grep -cF 'var k = e[0] + ">" + e[1];' "$S/template.html")" "1"
chk "walk tasks still get the amber classDef" \
  "$(grep -c 'classDef walk fill:#b45309' "$S/template.html")" "1"
chk "a single-task plan suppresses the graph" \
  "$(grep -cF 'if (tasks.length < 2) return null;' "$S/template.html")" "1"

# A9. tasks[0].parentNode is #content only while planTasks() returns siblings of
# the sentinel. Task 15's compareDocumentPosition filter also matches an h3
# marked nests inside an <li>, and the diagram would be buried in that list
# item. Anchoring to planH2 is correct now and survives Task 15 unchanged.
chk "insertion no longer anchors on the first task's parent" \
  "$(grep -cF 'tasks[0].parentNode' "$S/template.html")" "0"
chk "box and caption are both inserted at the sentinel's next sibling" \
  "$(grep -cF 'planH2.parentNode.insertBefore' "$S/template.html")" "2"
# .dag-caption pulls itself up under the diagram with margin-top:-8px, so the
# box has to be inserted first. Both calls target the same anchor, which makes
# source order the thing that decides DOM order -- a presence grep cannot see
# it, so assert the order.
dagbox_ln=$(grep -n 'insertBefore(box, anchor)' "$S/template.html" | head -1 | cut -d: -f1)
dagcap_ln=$(grep -n 'insertBefore(cap, anchor)' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$dagbox_ln" ] && [ -n "$dagcap_ln" ] && [ "$dagbox_ln" -lt "$dagcap_ln" ]; then
  ok "the diagram is inserted before its caption, which .dag-caption's negative top margin depends on"
else
  no "the diagram is inserted before its caption, which .dag-caption's negative top margin depends on" \
     "box=[${dagbox_ln:-missing}] cap=[${dagcap_ln:-missing}]"
fi

echo "== plan/template mirror =="
# Tasks 13, 14 and 15 quote this plan's code fences verbatim. A snippet that has
# drifted from the shipped file is a stale instruction, and nothing else in this
# suite can see it: the drift stays invisible until a later task applies the
# snippet and lands code that no longer matches what is here. Verifying it by
# hand in a scratchpad is exactly the check that is not there when it is needed.
#
# Written to generalise. mirror_chk takes (label, plan-fence first line, file,
# file first line, file stop line), so Task 16 can point it at every mirrored
# task rather than reinventing the extraction.
PLAN="$R/docs/plans/2026-07-30-visual-change-briefs.md"
# Trailing blank lines are an artifact of where each slice happens to end, not
# drift, and they are the only difference the two extractions legitimately have.
notrail(){ awk '{ l[NR] = $0 }
                 END { n = NR; while (n > 0 && l[n] ~ /^[[:space:]]*$/) n--;
                       for (i = 1; i <= n; i++) print l[i] }'; }
# Body of the fenced block in $1 whose first body line is exactly $2.
fence_body(){ awk -v m="$2" '$0 == m { on = 1 } on { if ($0 == "```") exit; print }' "$1" | notrail; }
# Lines of $1 from the line matching $2 up to but excluding the line matching $3.
file_slice(){ awk -v a="$2" -v b="$3" '$0 == a { on = 1 } on { if ($0 == b) exit; print }' "$1" | notrail; }
mirror_chk(){
  fence_body "$PLAN" "$2"       > "$W/mirror.plan"
  file_slice "$3"    "$4"  "$5" > "$W/mirror.file"
  # Both sides non-empty FIRST. A renamed plan, a reworded marker or a moved
  # block would otherwise leave two empty extractions comparing equal, and this
  # check would report PASS for a mirror it never actually looked at -- the
  # silent-success failure mode the Preflight calls out by name.
  if [ ! -s "$W/mirror.plan" ] || [ ! -s "$W/mirror.file" ]; then
    no "$1" "extraction empty: plan=$(wc -l < "$W/mirror.plan" | tr -d ' ')L file=$(wc -l < "$W/mirror.file" | tr -d ' ')L -- a marker moved or a file was renamed"
  elif diff -q "$W/mirror.plan" "$W/mirror.file" >/dev/null 2>&1; then
    ok "$1"
  else
    no "$1" "drifted on $(diff "$W/mirror.plan" "$W/mirror.file" | grep -c '^[<>]') lines; first: $(diff "$W/mirror.plan" "$W/mirror.file" | sed -n '2p' | cut -c1-80)"
  fi
}
DAG_HEAD='  /* ---------- task dependency graph, built from **Depends on:** ---------- */'
mirror_chk "Task 12's plan snippet is byte-identical to the shipped template" \
  "$DAG_HEAD" "$S/template.html" "$DAG_HEAD" '  /* ---------- walk-tag badges ---------- */'

echo "== template JS: mermaid contract =="
chk "no v8/v9 callback form" \
  "$(grep -c 'mermaid.render(id, src, function' "$S/template.html")" "0"
chk "strict security level" \
  "$(grep -c 'securityLevel:"strict"' "$S/template.html")" "1"
# strict is not enough on its own: at strict, mermaid still builds flowchart
# labels with innerHTML, and DOMPurify keeps <img> -- so a heading carrying an
# image tag beacons the reader's IP and open-time from a file that is supposed
# to be inert. htmlLabels:false is what closes it.
chk "flowchart labels are SVG text, never innerHTML" \
  "$(grep -c 'htmlLabels:false' "$S/template.html")" "1"
# ...and initialize() is not a control over untrusted content on its own.
# Mermaid 10.9.1 lets a %%{init: ...}%% directive -- or the equivalent YAML
# frontmatter, which funnels through the same addDirective -- override any key
# absent from its `secure` list, whose stock value omits every key this file
# depends on. themeCSS is the sharpest: concatenated verbatim into the emitted
# <style> at top level, checked only for balanced braces, so a payload can add
# an @font-face plus a rule that uses it and the browser fetches the font from
# a host of its choosing. Reproduced on real render.sh output by fence, by
# frontmatter, and through Task 12's generated DAG label. Pinned exact: dropping
# any one key silently reopens a route, and nothing else in this suite sees it.
chk "every config key that reaches CSS, markup or a URL is out of directive reach" \
  "$(grep -cF 'secure:["secure","securityLevel","startOnLoad","maxTextSize","maxEdges","htmlLabels","theme","themeCSS","fontFamily","altFontFamily"],' "$S/template.html")" "1"
chk "failing pass never clobbers a good render" \
  "$(grep -c 'box.querySelector(".d-light svg")' "$S/template.html")" "1"
# ...but it must not do so silently. That early return was the only path in the
# section producing neither a DOM signal nor a console line: a box that is a
# correct diagram in light and an empty card in dark, with nothing to say why.
chk "a pass that fails over an existing good render still reports" \
  "$(grep -cF 'warn("mermaid: " + pass.cls + " pass for an already-rendered diagram", err);' "$S/template.html")" "1"
# Mermaid serialises parse AND render through one internal queue drained by
# `await task()`, and an abandoned task pins it permanently. Racing only render
# leaves parse as a path along which our own chain never terminates -- traced
# against the bundle, with render #1 hung a clean diagram's parse #2 was still
# pending at 3s. Both calls must be raced; assert both, separately, because a
# single grep for "raceQueue" would pass with either one of them unwrapped.
chk "parse is raced, not just render" \
  "$(grep -cF 'raceQueue(mermaid.parse(src), "Parse")' "$S/template.html")" "1"
chk "render is raced" \
  "$(grep -cF 'raceQueue(mermaid.render(id, src), "Render")' "$S/template.html")" "1"
# The race has to REJECT. A timeout that resolved would hand the success branch
# an undefined result and leave an empty slot with no error card and no console
# line -- the exact silence the race exists to remove.
chk "the timeout rejects rather than resolving" \
  "$(grep -cF 'reject(new Error(what + " timed out after "' "$S/template.html")" "1"
# A timeout means one of two things and they need opposite responses: a pinned
# queue, where no later box can succeed and waiting a full budget for each is 32s
# of dead time on a four-box document; or a legitimately slow render, where the
# queue is healthy and every later box would have rendered fine. Latching
# unconditionally turns the second case into a document-wide failure -- measured
# against a box completing at 9s, an unconditional latch gave 4 error cards and
# 0 of 4 diagrams, where the pre-latch design cost 1 card and kept 3 diagrams.
# So the first timeout probes and only the second latches. Assert the ORDER of
# those two effects, not merely that both strings exist: an assignment that
# latched first and probed second would satisfy any presence grep while
# reinstating exactly the behaviour this replaced.
chk "the first timeout probes rather than latching" \
  "$(grep -cF 'else probing = true;          /* first timeout: diagnose before latching */' "$S/template.html")" "1"
chk "the wedge latches only when the probe itself times out" \
  "$(grep -cF 'if (probing) wedged = true;   /* the probe timed out too: really pinned */' "$S/template.html")" "1"
# The probe has to be retired by ANY settle, or one false positive would leave
# every later box on the short budget for the rest of the document.
# Pinned by its indent, which is what separates the assignment inside the settle
# handler from the `var probing = false;` declaration at section scope.
chk "anything settling retires the probe and restores full budgets" \
  "$(grep -cF '          probing = false;' "$S/template.html")" "1"
chk "the probe runs on its own shorter budget" \
  "$(grep -cF 'var budget = probing ? PROBE_TIMEOUT_MS : RENDER_TIMEOUT_MS;' "$S/template.html")" "1"
# ...and the budget is read once, at call time. Read inside the timer instead,
# a flag flipped by another box would change the budget an in-flight attempt is
# judged on, which is unreproducible by construction.
chk "the budget is fixed at call time, not read from the flag when the timer fires" \
  "$(grep -cF '}, budget);' "$S/template.html")" "1"
chk "a wedged queue fails the remaining boxes instead of waiting for each" \
  "$(grep -c 'if (wedged) throw new Error' "$S/template.html")" "1"
# Both themes for one box before moving to the next. With the wedge permanent,
# two sweeping passes leave every box before the stall holding a light render
# and no dark one -- and in dark theme CSS hides .d-light and finds no .d-dark,
# so a dark reader gets blank cards for diagrams that rendered fine.
chk "the two theme passes are interleaved per box, not swept per theme" \
  "$(grep -cF 'var PASSES = [{ theme:"default", cls:"d-light" }, { theme:"dark", cls:"d-dark" }];' "$S/template.html")" "1"
chk "both passes run inside one per-box reduce" \
  "$(grep -cF 'return PASSES.reduce(function(chain, pass){' "$S/template.html")" "1"
# Mermaid removes its temp container only on the success path; both failure
# exits throw with it still attached to <body>, where it shows mermaid's own
# error graphic outside .shell, unclassed, in both themes and in print.
chk "both of mermaid's orphaned temp container ids are cleaned up" \
  "$(grep -cF '["d" + id, "i" + id].forEach(function(orphan){' "$S/template.html")" "1"
# "on every failure path" is an ordering claim, not a presence one: placed after
# the no-clobber early return, the cleanup would skip that path and leave the
# orphan attached. Line numbers are what can see that.
orphan_ln=$(grep -n '\["d" + id, "i" + id\].forEach' "$S/template.html" | head -1 | cut -d: -f1)
noclob_ln=$(grep -n 'if (box.querySelector(".d-light svg"))' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$orphan_ln" ] && [ -n "$noclob_ln" ] && [ "$orphan_ln" -lt "$noclob_ln" ]; then
  ok "the orphan cleanup runs before the no-clobber early return, so it covers every failure path"
else
  no "the orphan cleanup runs before the no-clobber early return, so it covers every failure path" \
     "cleanup=[${orphan_ln:-missing}] no-clobber=[${noclob_ln:-missing}]"
fi
# Containment for the one section this task adds, by label and floor, per the
# doctrine at the top of the IIFE.
chk "guarded: mermaid: start dual-theme render" \
  "$(grep -cF 'guard("mermaid: start dual-theme render"' "$S/template.html")" "1"
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 16 ] && ok "at least 16 top-level sections guarded (floor raised by this task)" \
  || no "at least 16 top-level sections guarded (floor raised by this task)" "$n"
# guard() is synchronous-only. It sees the querySelectorAll and the reduce that
# builds the chain, and nothing after the first tick -- every mermaid.initialize
# now runs inside a .then, per box and per theme, where a throw is a rejection
# guard() structurally cannot see. Without a terminal .catch those surface as
# unhandled rejections: no label, nothing the console can pin on this file.
chk "the render chain has a terminal catch, not just a guard" \
  "$(grep -cF '      .catch(function(e){' "$S/template.html")" "1"
chk "the terminal catch reports through warn(), like every guarded section" \
  "$(grep -cF 'warn("mermaid: dual-theme render chain", e);' "$S/template.html")" "1"
# ...and it has to be chained after the reduce, or it covers only part of the
# run. Presence greps cannot see chain order; line numbers can.
reduce_ln=$(grep -n 'return chain.then(function(){ return renderBox(box); });' "$S/template.html" | head -1 | cut -d: -f1)
mmcatch_ln=$(grep -n 'warn("mermaid: dual-theme render chain"' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$reduce_ln" ] && [ -n "$mmcatch_ln" ] && [ "$reduce_ln" -lt "$mmcatch_ln" ]; then
  ok "the terminal catch is chained after the per-box reduce, so it covers the whole run"
else
  no "the terminal catch is chained after the per-box reduce, so it covers the whole run" \
     "reduce=[${reduce_ln:-missing}] catch=[${mmcatch_ln:-missing}]"
fi
# One writer for the marker, so the run-level deadline cannot overwrite a real
# verdict and a late completion cannot overwrite the deadline's.
chk "the completion marker has exactly one writer" \
  "$(grep -c 'root.setAttribute("data-diagrams"' "$S/template.html")" "1"
chk "first writer wins, so the marker never flaps" \
  "$(grep -cF 'if (!root.hasAttribute("data-diagrams")) root.setAttribute("data-diagrams", state);' "$S/template.html")" "1"
# Four states, because four things genuinely differ, and a harness that cannot
# tell them apart is back to the ambiguity the marker exists to remove:
# the run finished; it died; it never finished; mermaid was never on the page.
# Counts, not mere presence: "failed" is written from two distinct sites -- the
# terminal .catch and the synchronous fallback for a guard()-caught throw -- and
# an assertion expecting one of them would have to be relaxed to hide the other,
# which is how a real site goes missing unnoticed.
for pair in "done:1" "failed:2" "stalled:1" "unavailable:1"; do
  st=${pair%%:*}; want=${pair##*:}
  chk "run state marked: $st (x$want)" "$(grep -c "markRun(\"$st\")" "$S/template.html")" "$want"
done
# A guard()-caught synchronous throw means the chain never starts, so neither
# .then nor .catch can run -- observed at 63s with the attribute still absent.
chk "a guard()-caught throw still ends with a marker, not silence" \
  "$(grep -cF 'if (!diagramsStarted) { markRun("failed"); clearTimeout(runDeadline); }' "$S/template.html")" "1"
# Wedge detection already bounds a stalled run to one timeout, but this section
# has twice been certain a class of hang was closed and been wrong.
chk "a run-level deadline marks the run even if nothing else does" \
  "$(grep -cF 'var runDeadline = setTimeout(function(){ markRun("stalled"); }, RUN_DEADLINE_MS);' "$S/template.html")" "1"
# Same mirror as Task 12's, for the same reason: this task's snippet has been
# edited in the plan more than once, so plan and template can drift and nothing
# else in this suite can see it.
#
# Retargeted by Task 14. The stop marker was the IIFE's closing "})();" only
# because this renderer was then the last section in the file; Task 14 appends
# the index after it, so the marker is now the index's own header comment.
MMD_HEAD='  /* ---------- mermaid: v10 async contract, both themes rendered up front ---------- */'
TOC_HEAD='  /* ---------- build TOC ---------- */'
mirror_chk "Task 13's plan snippet is byte-identical to the shipped template" \
  "$MMD_HEAD" "$S/template.html" "$MMD_HEAD" "$TOC_HEAD"

echo "== template JS: index =="
chk "index built from h2/h3 only" \
  "$(grep -c 'content.querySelectorAll("h2, h3")' "$S/template.html")" "2"
chk "tasks attach by document position" \
  "$(grep -c 'DOCUMENT_POSITION_FOLLOWING' "$S/template.html")" "1"
chk "scrollspy observer present" "$(grep -c 'IntersectionObserver' "$S/template.html")" "1"
chk "mobile sidebar toggle wired" "$(grep -c 'sbToggle' "$S/template.html")" "2"

# Containment for the three sections this task adds, by label, per the doctrine.
for label in \
  'guard("index: build"' \
  'guard("index: scrollspy"' \
  'guard("index: mobile sidebar"' \
; do
  chk "guarded: $label" "$(grep -cF "$label" "$S/template.html")" "1"
done
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 19 ] && ok "at least 19 top-level sections guarded (floor raised by this task)" \
  || no "at least 19 top-level sections guarded (floor raised by this task)" "$n"

# Three guards rather than one, and this is the assertion that makes that
# structural rather than stylistic. The three labels above all still appear if
# the scrollspy and the sidebar are folded into one guard body, so they prove
# nothing about containment on their own. What has to hold is that the toggle is
# wired by a guard that OPENS AFTER the observer statement: an engine without
# that constructor throws in the scrollspy, and on a narrow viewport the toggle
# is the only way to reach the index at all, so it must not be reachable from
# that throw.
obs_ln=$(grep -n 'new IntersectionObserver' "$S/template.html" | head -1 | cut -d: -f1)
sbg_ln=$(grep -n 'guard("index: mobile sidebar"' "$S/template.html" | head -1 | cut -d: -f1)
sbt_ln=$(grep -n 'getElementById("sbToggle")' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$obs_ln" ] && [ -n "$sbg_ln" ] && [ -n "$sbt_ln" ] &&
   [ "$obs_ln" -lt "$sbg_ln" ] && [ "$sbg_ln" -lt "$sbt_ln" ]; then
  ok "the sidebar toggle is wired by a guard that opens after the scrollspy observer"
else
  no "the sidebar toggle is wired by a guard that opens after the scrollspy observer" \
     "observer=[${obs_ln:-missing}] sidebar guard=[${sbg_ln:-missing}] toggle=[${sbt_ln:-missing}]"
fi

# `toc` is read by all three sections. Wrapping its declaration inside the build
# guard would scope it to that callback and leave the scrollspy and the sidebar
# throwing a ReferenceError under someone else's label -- the sectionNodes
# precedent. Anchored at indent 2 for the same reason that one is: an unanchored
# grep still finds the declaration after it has been moved inside a guard(), so
# the assertion would keep passing through the exact regression it names.
chk "the toc handle stays a declaration at IIFE scope, not inside a guard()" \
  "$(grep -c '^  var toc = document.getElementById("toc");$' "$S/template.html")" "1"

# The scrollspy reads the links out of #toc, which only exist once the build
# section has appended them. The declarations hoist; the appendChild does not.
# A scrollspy guard placed first sees an empty nav, registers no links, and the
# index never highlights -- with nothing on the page or in the console to say
# so. Presence greps cannot see that; assert the source order it depends on.
build_ln=$(grep -n 'guard("index: build"' "$S/template.html" | head -1 | cut -d: -f1)
spy_ln=$(grep -n 'guard("index: scrollspy"' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$build_ln" ] && [ -n "$spy_ln" ] && [ "$build_ln" -lt "$spy_ln" ]; then
  ok "the scrollspy is wired after the index has been appended"
else
  no "the scrollspy is wired after the index has been appended" \
     "build=[${build_ln:-missing}] scrollspy=[${spy_ln:-missing}]"
fi

mirror_chk "Task 14's plan snippet is byte-identical to the shipped template" \
  "$TOC_HEAD" "$S/template.html" "$TOC_HEAD" '})();'
# NOTE FOR TASK 15: the stop marker above is the IIFE's closing "})();", correct
# only while the mobile sidebar is the last section in the file. Rather than hand
# Task 15 the same puzzling hundred-line diff on someone else's mirror that Task
# 13 handed this one, the invariant that marker rests on is pinned separately
# here, by a label that says what to do about it. Appending a section after the
# sidebar fails both checks -- this is the one that names the fix.
after_sb=$(awk '/^  \/\* ---------- mobile sidebar ---------- \*\/$/ { seen = 1; next }
                seen && /^  \/\* ---------- / { n++ }
                END { print n + 0 }' "$S/template.html")
chk "no section follows the mobile sidebar (retarget the Task 14 mirror stop marker if one must)" \
  "$after_sb" "0"

echo
echo "shell: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
