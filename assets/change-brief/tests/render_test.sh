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
[ -f "$W/x.html" ] && no "  leaves no output file" "file exists" || ok "  leaves no output file"

"$S/render.sh" "$W/spec.md" -o "$W/x.html" -V "$W/novendor" >/dev/null 2>"$W/err.txt"
chk "missing vendor exits 1" "$?" "1"

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

echo
echo "shell: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
