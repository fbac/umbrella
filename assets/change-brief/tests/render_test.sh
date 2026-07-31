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

echo
echo "shell: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
