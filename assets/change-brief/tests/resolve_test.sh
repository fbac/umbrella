#!/usr/bin/env bash
# Verifies $BRIEF_DIR resolution from an INSTALLED plugin, not the working tree.
# Run after the plugin has been installed or re-installed from this repo.
#
#   bash assets/change-brief/tests/resolve_test.sh
set -uo pipefail
pass=0; fail=0
ok(){ printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s :: %s\n' "$1" "${2:-}"; fail=$((fail+1)); }

CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/umbrella/umbrella"
INSTALL="$(ls -d "$CACHE"/*/ 2>/dev/null | sort -V | tail -1)"

if [ -z "$INSTALL" ]; then
  echo "  SKIP  umbrella is not installed under $CACHE"
  echo "        install the plugin, then re-run this script"
  exit 0
fi
echo "install: $INSTALL"

for skill in brainstorming writing-plans; do
  BASE="${INSTALL}skills/$skill"
  [ -d "$BASE" ] || { no "$skill base dir exists" "$BASE"; continue; }
  BRIEF_DIR="$BASE/../../assets/change-brief"
  [ -x "$BRIEF_DIR/render.sh" ] && ok "$skill: \$BRIEF_DIR/render.sh is executable" \
    || no "$skill: \$BRIEF_DIR/render.sh is executable" "$BRIEF_DIR"
  [ -r "$BRIEF_DIR/BLOCKS.md" ] && ok "$skill: \$BRIEF_DIR/BLOCKS.md is readable" \
    || no "$skill: \$BRIEF_DIR/BLOCKS.md is readable" "$BRIEF_DIR"
  [ -r "$BRIEF_DIR/vendor/mermaid.min.js" ] && ok "$skill: vendor bundle is readable" \
    || no "$skill: vendor bundle is readable" "$BRIEF_DIR"
done

# End to end from the resolved path.
BASE="${INSTALL}skills/brainstorming"
BRIEF_DIR="$BASE/../../assets/change-brief"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
printf '# Resolve Test\n\n## Why this change\n\nbody\n' > "$W/s.md"
if "$BRIEF_DIR/render.sh" "$W/s.md" -o "$W/o.html" >/dev/null 2>&1 && [ -s "$W/o.html" ]; then
  ok "render.sh runs from the resolved path"
else
  no "render.sh runs from the resolved path" "render failed"
fi

echo
echo "resolve: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
