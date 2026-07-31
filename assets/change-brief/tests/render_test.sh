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

echo
echo "shell: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
