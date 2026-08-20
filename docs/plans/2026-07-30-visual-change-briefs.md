# Visual Change Briefs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use umbrella:subagent-driven-development (recommended) or umbrella:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. During per-task and final review, ALSO apply umbrella:review-lens (composed-surface-per-persona + walk-only flagging).

**Goal:** Render every umbrella spec and plan into a self-contained, navigable, diagram-bearing HTML brief so the human review gates stop degrading into skimming.

**Architecture:** A POSIX bash assembler (`render.sh`) concatenates the spec, a sentinel-marked `## Plan` heading, and either the plan body or a pending callout; base64-encodes the result into a single HTML template that inlines vendored `marked` and `mermaid`. All markdown parsing happens in the browser with the same parser the reader sees. Truncation is proven structurally by asserting the sentinel survived parsing, not by counting headings in awk.

**Tech Stack:** bash, awk, sed, base64, shasum; marked 12.0.2 and mermaid 10.9.1 vendored as files; optional playwright-core for a headless smoke test.

**Spec:** `docs/specs/2026-07-27-visual-change-briefs-design.md`

---

## Preflight

Read the spec before starting, especially **Known open findings** — six defects are already characterised there and Task 15 fixes them. Do not rediscover them.

Two rules govern every test in this plan, both from assertions that looked green while checking nothing:

- Every assertion must feed the pass/fail counters, and the script must exit non-zero on failure.
- An assertion must fail if its fixture never got built. A check that reads a file the renderer refused to create must not fall back to `0` and print PASS.

All paths are relative to the repo root `/Users/fbac/projects/umbrella`.

---

### Task 1: Repository scaffold and gitignore — `static-verifiable`

**Depends on:** none

**Files:**
- Create: `.gitignore`
- Create: `assets/change-brief/` (directory)
- Create: `assets/change-brief/vendor/` (directory)
- Create: `assets/change-brief/tests/fixtures/` (directory)
- Create: `assets/change-brief/tests/browser/` (directory)

- [ ] **Step 1: Write the failing test**

Create `assets/change-brief/tests/render_test.sh` with just the harness and one assertion:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: `FAIL gitignore excludes docs/briefs/ :: missing`, exit 1.

- [ ] **Step 3: Create the gitignore and directories**

Create `.gitignore`:

```gitignore
docs/briefs/
```

Then:

```bash
mkdir -p assets/change-brief/vendor assets/change-brief/tests/fixtures assets/change-brief/tests/browser
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: `PASS gitignore excludes docs/briefs/`, `shell: 1 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
chmod +x assets/change-brief/tests/render_test.sh
git add .gitignore assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): scaffold assets dir and gitignore derived briefs"
```

---

### Task 2: Vendor marked and mermaid at pinned versions — `static-verifiable`

**Depends on:** Task 1

The brief must issue zero network requests on load, so both libraries ship as files in the repo. They are vendored as separate files rather than inlined into `template.html` so that editing the template costs ~28KB of git history instead of 3.4MB.

**Files:**
- Create: `assets/change-brief/vendor/marked.min.js`
- Create: `assets/change-brief/vendor/mermaid.min.js`
- Create: `assets/change-brief/vendor/README.md`
- Modify: `assets/change-brief/tests/render_test.sh`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: four FAILs for the missing vendor files, exit 1.

- [ ] **Step 3: Download the pinned versions**

This is the one step in the plan that needs network access. It runs once, at build time — `render.sh` itself never touches the network.

```bash
curl -fsSL -o assets/change-brief/vendor/marked.min.js \
  https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js
curl -fsSL -o assets/change-brief/vendor/mermaid.min.js \
  https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js
```

Create `assets/change-brief/vendor/README.md`:

```markdown
# Vendored libraries

Committed so a rendered brief opens from `file://` with zero network requests.

| File | Package | Version | sha256 |
|---|---|---|---|
| `marked.min.js` | marked | 12.0.2 | `15fabce5b65898b32b03f5ed25e9f891a729ad4c0d6d877110a7744aa847a894` |
| `mermaid.min.js` | mermaid | 10.9.1 | `61b335a46df05a7ce1c98378f60e5f3e77a7fb608a1056997e8a649304a936d6` |

Both are MIT licensed.

## Why these versions are pinned

The template depends on version-specific API contracts:

- **mermaid 10 is async-only.** `parse()` returns a Promise and rejects rather than
  throwing; `render(id, text, container)` takes an `Element` third argument, not a
  callback. The mermaid 8/9 callback form produces no output and no exception —
  every diagram silently blank, valid and invalid alike.
- **marked 12** routes both block-level and inline HTML through `renderer.html`,
  which is what makes the inertness guarantee hold.

To upgrade, re-run the smoke test in `../tests/browser/verify.mjs` and the walk
cases in the plan's Browser-Walk Inventory. Update the checksums above and in
`../tests/render_test.sh`.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: `PASS vendor/marked.min.js present`, `PASS marked sha256 pinned`, `PASS mermaid sha256 pinned`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/vendor/
git commit -m "feat(change-brief): vendor marked 12.0.2 and mermaid 10.9.1 with pinned checksums"
```

---

### Task 3: `scan.awk` block scanner — `static-verifiable`

**Depends on:** Task 1

The scanner deliberately does **not** reimplement CommonMark. It does only the two things that must happen before parsing — neutralising a dangling HTML comment and flattening stray H1s — plus reporting structural defects. Everything else moved to the page.

**Files:**
- Create: `assets/change-brief/scan.awk`
- Modify: `assets/change-brief/tests/render_test.sh`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: every scan.awk assertion FAILs (awk cannot read `scan.awk`), exit 1.

- [ ] **Step 3: Write the scanner**

Create `assets/change-brief/scan.awk`:

```awk
# scan.awk — minimal block scanner for change-brief payloads.
#
# SCOPE DISCIPLINE: this file does NOT try to reimplement CommonMark. Four
# review rounds established that it cannot. Every attempt to make a source-side
# heading count agree with marked's parse produced a new divergence — nested
# fences, indented code, HTML blocks, backtick info strings — and each
# divergence is either a false truncation alarm or silent content loss.
#
# Truncation is now detected by the PAGE, structurally: render.sh always
# appends a sentinel Plan heading, and the page asserts it survived the parse.
# That check uses the same parser the reader sees, so it cannot drift, and it
# catches every cause of content loss rather than the ones awk can model.
#
# What remains here is only what the page cannot do, because it happens before
# parsing: neutralising a dangling HTML comment, and flattening stray H1s.
#
# Modes:
#   -v mode=escape  emit the payload: demote stray H1s, and if -v unbalanced=1
#                   escape line-start "<!--" outside code
#   -v mode=diag    emit one warning line per structural defect found
#   -v mode=dangle  print 1 if a "<!--" is left unclosed outside code, else 0

function emit(l) { if (mode == "escape") print l }

# Fence marker, if this line opens or closes a fenced block. Approximate by
# design: a misread here only affects escaping and warnings, both of which the
# page's structural check backstops.
function marker_of(line,   m) {
  if (match(line, /^ {0,3}(`{3,}|~{3,})/)) {
    m = substr(line, RSTART, RLENGTH)
    sub(/^ +/, "", m)
    return m
  }
  return ""
}

# Flush the one-line lookback buffer used for setext detection.
function flush(   p) {
  if (held != "") { p = held; held = ""; emit(p) }
}

BEGIN { fchar = ""; flen = 0; prevblank = 1; incode = 0; incomment = 0; held = "" }

{
  line = $0

  # ---- setext H1: a run of "=" under a non-blank line ----------------------
  # Demoted like ATX H1s. The ATX regex cannot see these, so a setext H1
  # reaches the DOM as a real <h1>, opening an index group the h2/h3 builder
  # never renders — leaving that whole section unreachable.
  if (fchar == "" && !incode && held != "" && line ~ /^ {0,3}=+[ \t]*$/) {
    emit("#### " held)
    held = ""
    next
  }

  m = marker_of(line)

  if (m != "") {
    flush()
    ch = substr(m, 1, 1); len = length(m)
    if (fchar == "") { fchar = ch; flen = len; prevblank = 0; incode = 0; emit(line); next }
    if (ch == fchar && len >= flen && line ~ /^ {0,3}(`+|~+)[ \t]*$/) {
      fchar = ""; flen = 0; prevblank = 0; emit(line); next
    }
    prevblank = 0; emit(line); next
  }

  if (fchar != "") { flush(); emit(line); next }

  if (line ~ /^[ \t]*$/) { flush(); prevblank = 1; incode = 0; emit(line); next }

  if ((prevblank || incode) && line ~ /^(    |\t)/) {
    flush(); incode = 1; prevblank = 0; emit(line); next
  }
  incode = 0; prevblank = 0

  # ---- dangling block-comment detection ------------------------------------
  # Only a comment that OPENS AT LINE START can form a CommonMark HTML block
  # and swallow the document. A "<!--" mid-paragraph is inline HTML and is
  # harmless, so tracking those produces false alarms on any document that
  # merely discusses comments in prose or inline code — this spec does.
  #
  # Order matters, not totals: a stray "-->" earlier in the text (prose about
  # mermaid arrows, say) would balance a count and disable escaping while a
  # real dangling opener still swallowed the tail.
  if (!incomment && line ~ /^ {0,3}<!--/) incomment = 1
  if (incomment) {
    t = line
    while (incomment && match(t, /-->/)) { incomment = 0; t = substr(t, RSTART + 3) }
  }

  flush()

  # ---- H1 flattening --------------------------------------------------------
  # To h4, not h2. A demoted H2 opens an index group and steals the following
  # H3s exactly as the H1 did — the defect renamed rather than removed. h4 is
  # below the index's h2/h3 range, so it can neither open nor capture a group.
  if (line ~ /^ {0,3}# /) sub(/#/, "####", line)

  if (unbalanced && line ~ /^ {0,3}<!--/) sub(/<!--/, "\\&lt;!--", line)

  # Hold non-blank lines one line back so the next line can turn them into a
  # setext heading. Only text lines can be setext content.
  if (mode == "escape" && line !~ /^ {0,3}(#|>|[-*+] |[0-9]+[.)] )/) { held = line; next }
  emit(line)
}

END {
  flush()
  if (mode == "dangle") print (incomment ? 1 : 0)
  if (mode == "diag") {
    if (fchar != "")
      print "Unterminated code fence: a ``` or ~~~ block was opened and never closed, so everything after it is being shown as code."
    if (incomment)
      print "Unterminated HTML comment: a <!-- was opened and never closed. It has been neutralised so the rest of the document still renders."
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: all nine scan.awk assertions PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/scan.awk assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): add minimal block scanner for pre-parse transforms"
```

---

### Task 4: `render.sh` CLI, preconditions and post-conditions — `static-verifiable`

**Depends on:** Task 1

Preconditions assert every placeholder is **present exactly once**. Checking only that none *survives* passes a template with one deleted, which yields a blank brief and exit 0.

**Files:**
- Create: `assets/change-brief/render.sh`
- Modify: `assets/change-brief/tests/render_test.sh`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: FAILs because `render.sh` does not exist (exit 127, not 1), exit 1.

- [ ] **Step 3: Write the CLI and guard rails**

Create `assets/change-brief/render.sh` with the top half only. Tasks 5 and 6 append to it.

```bash
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
    -o) OUT="${2:-}"; shift 2 ;;
    -t) TPL="${2:-}"; shift 2 ;;
    -V) VENDOR="${2:-}"; shift 2 ;;
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
# A supplied-but-unreadable plan must fail loudly. Falling through to the
# pending callout would tell the human "no plan exists yet" when one does.
if [ -n "$PLAN" ] && [ ! -r "$PLAN" ]; then
  echo "render.sh: cannot read plan $PLAN" >&2; exit 1
fi
[ -r "$VENDOR/marked.min.js"  ] || { echo "render.sh: missing $VENDOR/marked.min.js"  >&2; exit 1; }
[ -r "$VENDOR/mermaid.min.js" ] || { echo "render.sh: missing $VENDOR/mermaid.min.js" >&2; exit 1; }

# Assert every placeholder is PRESENT before substituting. Checking only that
# none survives passes a template with one deleted, yielding an empty brief and
# a zero exit status.
for ph in __TITLE_B64__ __SOURCES_B64__ __GENERATED__ __DIAG_B64__ __PLANSTATE__ __VENDOR_JS__ __BRIEF_B64__; do
  n=$(grep -c "$ph" "$TPL" || true)
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
```

Make it executable: `chmod +x assets/change-brief/render.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: the five precondition assertions PASS. The script exits before producing output, which is correct at this stage — Tasks 5 and 6 complete it.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/render.sh assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): render.sh CLI, placeholder preconditions, failure cleanup"
```

---

### Task 5: `render.sh` payload assembly — `static-verifiable`

**Depends on:** Task 2, Task 4

Both documents' leading H1 is dropped: the spec's title is already the masthead and the plan's would be a second H1 mid-document. The strip is **first-line-only** — a "first `^# ` anywhere" rule is fence-unaware and silently deletes a `# comment` line from a bash fence in a plan that has no H1.

**Files:**
- Modify: `assets/change-brief/render.sh` (append)
- Modify: `assets/change-brief/tests/render_test.sh`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== payload assembly =="
# Helper: decode the base64 payload out of a rendered brief.
payload(){ python3 - "$1" <<'PY'
import sys, re, base64
h = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'data-brief="([^"]*)"', h, re.S)
sys.stdout.write(base64.b64decode(re.sub(r'\s', '', m.group(1))).decode('utf-8'))
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: every payload assertion FAILs — `render.sh` produces no output file yet.

- [ ] **Step 3: Append payload assembly to render.sh**

Append to `assets/change-brief/render.sh`:

```bash
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
```

- [ ] **Step 4: Verify what is verifiable at this point**

The payload assertions stay **red** until Task 7 supplies `template.html` — `render.sh`
exits at the `[ -r "$TPL" ]` precondition before reaching payload assembly. That is
expected staging, not a defect. Re-run the full suite after Task 7.

What must pass now:

Run: `bash -n assets/change-brief/render.sh && grep -cF 'Plan\342\201\240' assets/change-brief/render.sh`
Expected: the syntax check exits 0, and the grep prints `1` — the sentinel heading is
appended ahead of both the plan-attached and plan-pending branches.

Run: `grep -c 'strip_bom\|has_front_matter\|strip_h1' assets/change-brief/render.sh`
Expected: `7` or more — all three helpers are defined and called.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/render.sh assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): payload assembly with BOM, front-matter and sentinel handling"
```

---

### Task 6: `render.sh` diagnostics, provenance, encoding and injection — `static-verifiable`

**Depends on:** Task 3, Task 5

`sed` addresses for the two large injections are **anchored**. An unanchored `/__VENDOR_JS__/` also matches a template comment that merely mentions the placeholder, injecting the 3.3MB bundle twice.

**Files:**
- Modify: `assets/change-brief/render.sh` (append)
- Modify: `assets/change-brief/tests/render_test.sh`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
"$S/render.sh" "$W/s.md" -o "$W/d1.html" >/dev/null
d1=$(grep -o 'data-sources="[^"]*"' "$W/d1.html")
printf '# Spec Title\n\n## Design\n\nbody changed\n' > "$W/s2.md"
"$S/render.sh" "$W/s2.md" -o "$W/d2.html" >/dev/null
d2=$(grep -o 'data-sources="[^"]*"' "$W/d2.html")
[ "$d1" != "$d2" ] && ok "provenance changes with source bytes" \
  || no "provenance changes with source bytes" "identical"

# Idempotent apart from the generation timestamp.
"$S/render.sh" "$W/s.md" -o "$W/i1.html" >/dev/null
"$S/render.sh" "$W/s.md" -o "$W/i2.html" >/dev/null
if diff <(sed 's/data-generated="[^"]*"/X/' "$W/i1.html") \
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: FAILs — no HTML output exists yet.

- [ ] **Step 3: Append the remainder of render.sh**

Append to `assets/change-brief/render.sh`:

```bash
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: everything from Tasks 4, 5 and 6 PASSes once Task 7 has produced `template.html`. If Task 7 is not yet done, the suite still fails on "cannot read template" — run this task's tests again after Task 7.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/render.sh assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): diagnostics, sha256 provenance, anchored sed injection"
```

---

### Task 7: `template.html` shell, CSS and placeholders — `static-verifiable`

**Depends on:** Task 2, Task 5

Each placeholder appears **exactly once** and must never be named in a comment — `render.sh` rejects a template that mentions one twice.

**Files:**
- Create: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: all placeholder assertions FAIL — `template.html` does not exist.

- [ ] **Step 3: Create the template shell**

Create `assets/change-brief/template.html`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Change Brief</title>
<style>
:root{
  --bg:#fbfbfa; --bg-alt:#f3f3f1; --bg-code:#f0f0ee;
  --fg:#1c1c1a; --fg-dim:#65655f; --fg-faint:#8f8f87;
  --line:#e2e2dd; --line-strong:#c9c9c2;
  --accent:#4f46e5; --accent-soft:#eeecfd;
  --warn:#b45309; --warn-soft:#fdf3e3;
  --danger:#b91c1c; --danger-soft:#fdeceb;
  --ok:#15803d; --ok-soft:#e9f6ed;
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
  --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Helvetica,Arial,sans-serif;
}
:root[data-theme="dark"]{
  --bg:#15151a; --bg-alt:#1d1d24; --bg-code:#20202a;
  --fg:#e6e6ea; --fg-dim:#a0a0ad; --fg-faint:#75757f;
  --line:#2b2b35; --line-strong:#3d3d4a;
  --accent:#8b85f5; --accent-soft:#232135;
  --warn:#f0a35e; --warn-soft:#2c2318;
  --danger:#f08a84; --danger-soft:#2e1c1c;
  --ok:#6ddc95; --ok-soft:#16281d;
}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
body{
  background:var(--bg); color:var(--fg);
  font-family:var(--sans); font-size:15.5px; line-height:1.65;
  -webkit-font-smoothing:antialiased;
}
a{color:var(--accent); text-decoration:none}
a:hover{text-decoration:underline}

.shell{display:flex; min-height:100vh}
.sidebar{
  width:290px; flex:0 0 290px; border-right:1px solid var(--line);
  background:var(--bg-alt); position:sticky; top:0; height:100vh;
  overflow-y:auto; padding:20px 0 40px;
}
.main{flex:1 1 auto; min-width:0; display:flex; justify-content:center; padding:0 32px 120px}
.doc{width:100%; max-width:860px}

.masthead{border-bottom:1px solid var(--line); padding:34px 0 22px; margin-bottom:34px}
.eyebrow{font-size:11px; letter-spacing:.11em; text-transform:uppercase; color:var(--fg-faint); font-weight:600; margin-bottom:10px}
.masthead h1{font-size:33px; line-height:1.2; margin:0 0 16px; letter-spacing:-.02em}
.stamps{display:flex; flex-wrap:wrap; gap:8px; align-items:center; font-size:12px}
.stamp{
  display:inline-flex; align-items:center; gap:6px;
  border:1px solid var(--line-strong); border-radius:999px;
  padding:3px 11px; color:var(--fg-dim); font-family:var(--mono); font-size:11.5px;
}

.toc-head{display:flex; align-items:center; justify-content:space-between; padding:0 20px 14px; margin-bottom:6px; border-bottom:1px solid var(--line)}
.toc-title{font-size:11px; letter-spacing:.11em; text-transform:uppercase; color:var(--fg-faint); font-weight:600}
.theme-toggle{display:flex; gap:2px; background:var(--bg); border:1px solid var(--line-strong); border-radius:7px; padding:2px}
.theme-toggle button{background:none; border:0; cursor:pointer; padding:3px 7px; border-radius:5px; color:var(--fg-dim); font-size:12px; line-height:1; font-family:var(--sans)}
.theme-toggle button[aria-pressed="true"]{background:var(--accent-soft); color:var(--accent)}
nav.toc{padding:10px 12px}
nav.toc ul{list-style:none; margin:0; padding:0}
.toc-group{margin-bottom:2px}
.toc-l2{display:flex; align-items:flex-start; gap:4px}
.chevron{background:none; border:0; cursor:pointer; color:var(--fg-faint); padding:5px 3px; line-height:1; font-size:10px; flex:0 0 auto; transition:transform .12s ease}
.chevron[aria-expanded="false"]{transform:rotate(-90deg)}
.toc-group.no-kids .chevron{visibility:hidden}
nav.toc a{display:block; padding:5px 8px; border-radius:6px; color:var(--fg-dim); font-size:13.5px; line-height:1.4; flex:1 1 auto}
nav.toc a:hover{background:var(--bg); color:var(--fg); text-decoration:none}
nav.toc a.lvl2{font-weight:550; color:var(--fg)}
nav.toc .kids{margin:0 0 4px 22px; border-left:1px solid var(--line); padding-left:6px}
nav.toc .kids a{font-size:13px; padding:4px 8px}
nav.toc a.active{background:var(--accent-soft); color:var(--accent); font-weight:600}
nav.toc .kids[hidden]{display:none}

.doc h2{font-size:25px; letter-spacing:-.015em; margin:52px 0 4px; padding-top:14px; border-top:1px solid var(--line); scroll-margin-top:20px}
.doc h2:first-of-type{border-top:0; margin-top:0}
.doc h3{font-size:18px; letter-spacing:-.01em; margin:34px 0 2px; scroll-margin-top:20px}
.doc h4{font-size:15px; margin:24px 0 2px; color:var(--fg-dim)}
.doc p{margin:12px 0}
.doc ul,.doc ol{margin:12px 0; padding-left:24px}
.doc li{margin:5px 0}
.doc li::marker{color:var(--fg-faint)}
.doc hr{border:0; border-top:1px solid var(--line); margin:44px 0}
.doc strong{font-weight:640}

code{font-family:var(--mono); font-size:.875em; background:var(--bg-code); padding:.13em .38em; border-radius:4px}
pre{background:var(--bg-code); border:1px solid var(--line); border-radius:9px; padding:14px 16px; overflow-x:auto; margin:16px 0}
pre code{background:none; padding:0; font-size:12.8px; line-height:1.6}

table{border-collapse:collapse; width:100%; margin:18px 0; font-size:14px; display:block; overflow-x:auto}
th,td{border:1px solid var(--line); padding:8px 12px; text-align:left; vertical-align:top}
th{background:var(--bg-alt); font-weight:620; font-size:12.5px; letter-spacing:.02em}
tbody tr:nth-child(even){background:var(--bg-alt)}
blockquote{margin:16px 0; padding:2px 0 2px 16px; border-left:3px solid var(--line-strong); color:var(--fg-dim)}

.callout{border-radius:9px; padding:13px 16px; margin:18px 0; border:1px solid; font-size:14.5px}
.callout .callout-label{font-size:11px; letter-spacing:.09em; text-transform:uppercase; font-weight:700; margin-bottom:5px; display:block}
.callout p:first-of-type{margin-top:0}
.callout p:last-child{margin-bottom:0}
.callout.note{border-color:var(--accent); background:var(--accent-soft)}
.callout.note .callout-label{color:var(--accent)}
.callout.warning{border-color:var(--warn); background:var(--warn-soft)}
.callout.warning .callout-label{color:var(--warn)}
.callout.important{border-color:var(--danger); background:var(--danger-soft)}
.callout.important .callout-label{color:var(--danger)}
.callout.tip{border-color:var(--ok); background:var(--ok-soft)}
.callout.tip .callout-label{color:var(--ok)}
.callout.pending{border:1px dashed var(--accent); background:var(--accent-soft); padding:22px 24px; border-radius:11px}
.callout.pending .callout-label{color:var(--accent); font-size:12px}

.badge{display:inline-block; font-family:var(--mono); font-size:10.5px; font-weight:600; letter-spacing:.03em; padding:3px 8px; border-radius:5px; vertical-align:middle; margin-left:8px}
.badge.static{background:var(--bg-code); color:var(--fg-dim); border:1px solid var(--line-strong)}
.badge.walk{background:var(--warn-soft); color:var(--warn); border:1px solid var(--warn)}

.doc li:has(> input[type=checkbox]){list-style:none; margin-left:-20px}
input[type=checkbox]{accent-color:var(--accent); margin-right:7px; transform:translateY(1px)}
li:has(> input[type=checkbox]:checked){color:var(--fg-faint)}
li:has(> input[type=checkbox]:checked) strong{text-decoration:line-through; font-weight:500}
.progress{display:inline-flex; align-items:center; gap:7px; font-family:var(--mono); font-size:11px; color:var(--fg-dim); margin-left:8px; vertical-align:middle}
.progress .bar{width:52px; height:5px; border-radius:3px; background:var(--line); overflow:hidden}
.progress .bar span{display:block; height:100%; background:var(--ok)}

/* diagrams: both theme variants rendered up front, toggled by CSS.
   No re-render on theme change, and print can select the light one synchronously. */
.mermaid-block{margin:20px 0; padding:18px; border:1px solid var(--line); border-radius:9px; background:var(--bg-alt); overflow-x:auto; text-align:center}
.mermaid-block svg{max-width:100%; height:auto}
.d-dark{display:none}
:root[data-theme="dark"] .d-light{display:none}
:root[data-theme="dark"] .d-dark{display:block}
.mermaid-error{margin:20px 0; border:1px solid var(--danger); border-radius:9px; background:var(--danger-soft); overflow:hidden}
.mermaid-error .err-head{padding:9px 14px; font-size:12px; font-weight:700; color:var(--danger); letter-spacing:.04em; text-transform:uppercase; border-bottom:1px solid var(--danger)}
.mermaid-error .err-msg{padding:10px 14px; font-family:var(--mono); font-size:12px; color:var(--danger); white-space:pre-wrap}
.mermaid-error pre{margin:0; border:0; border-top:1px solid var(--danger); border-radius:0; background:transparent}
.dag-caption{font-size:12px; color:var(--fg-faint); text-align:center; margin-top:-8px; font-family:var(--mono)}

.integrity-banner{
  border:1px solid var(--danger); background:var(--danger-soft); color:var(--danger);
  border-radius:9px; padding:13px 16px; margin:0 0 24px; font-size:14px;
}
.integrity-banner strong{display:block; margin-bottom:4px; text-transform:uppercase; font-size:11px; letter-spacing:.09em}
.img-chip{
  display:inline-flex; align-items:baseline; gap:7px; font-family:var(--mono); font-size:12px;
  border:1px dashed var(--line-strong); border-radius:6px; padding:3px 9px;
  color:var(--fg-dim); background:var(--bg-alt); word-break:break-all;
}
.img-chip b{font-weight:600; color:var(--fg-faint); font-size:10.5px; letter-spacing:.05em; text-transform:uppercase}

.sidebar-toggle{display:none; position:fixed; left:14px; top:14px; z-index:40; background:var(--bg-alt); border:1px solid var(--line-strong); border-radius:8px; padding:8px 12px; cursor:pointer; color:var(--fg); font-size:14px; line-height:1}
@media (max-width:900px){
  .sidebar{position:fixed; z-index:30; left:0; top:0; transform:translateX(-100%); transition:transform .18s ease; box-shadow:0 0 40px rgba(0,0,0,.18)}
  .sidebar.open{transform:translateX(0)}
  .sidebar-toggle{display:block}
  .main{padding:56px 18px 100px}
}

@media print{
  /* must out-specify :root[data-theme="dark"] — media queries add no specificity */
  :root, :root[data-theme="dark"]{
    --bg:#fff; --bg-alt:#fff; --bg-code:#f5f5f5;
    --fg:#000; --fg-dim:#333; --fg-faint:#555;
    --line:#ccc; --line-strong:#999;
    --accent:#3730a3; --accent-soft:#f4f3ff;
    --warn:#8a4406; --warn-soft:#fdf6ec;
    --danger:#991b1b; --danger-soft:#fdf0ef;
    --ok:#14532d; --ok-soft:#f0f8f2;
  }
  /* SVG fills are baked at render time, so force the light variant */
  :root[data-theme="dark"] .d-light, .d-light{display:block !important}
  :root[data-theme="dark"] .d-dark, .d-dark{display:none !important}
  .sidebar,.sidebar-toggle,.theme-toggle{display:none !important}
  .main{padding:0}
  .doc{max-width:none}
  .mermaid-block,pre,table,.callout,.mermaid-error{break-inside:avoid; page-break-inside:avoid}
  .doc h2,.doc h3{break-after:avoid; page-break-after:avoid}
  a{color:#000; text-decoration:underline}
}
</style>
<script>
__VENDOR_JS__
</script>
</head>
<body
  data-title="__TITLE_B64__"
  data-sources="__SOURCES_B64__"
  data-generated="__GENERATED__"
  data-diag="__DIAG_B64__"
  data-plan-state="__PLANSTATE__"
  data-brief="
__BRIEF_B64__
">

<button class="sidebar-toggle" id="sbToggle" aria-label="Toggle index">☰</button>

<div class="shell">
  <aside class="sidebar" id="sidebar">
    <div class="toc-head">
      <span class="toc-title">Contents</span>
      <div class="theme-toggle" role="group" aria-label="Theme">
        <button data-theme-set="auto"  aria-pressed="true"  title="Follow system">A</button>
        <button data-theme-set="light" aria-pressed="false" title="Light">☀</button>
        <button data-theme-set="dark"  aria-pressed="false" title="Dark">☾</button>
      </div>
    </div>
    <nav class="toc" id="toc"></nav>
  </aside>

  <main class="main">
    <div class="doc">
      <header class="masthead">
        <div class="eyebrow">Change Brief</div>
        <h1 id="briefTitle"></h1>
        <div class="stamps" id="briefStamps"></div>
      </header>
      <div id="content"></div>
    </div>
  </main>
</div>

<script>
(function(){
  "use strict";
})();
</script>
</body>
</html>
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: all placeholder assertions PASS, and the Task 4/5/6 assertions now pass too because a template exists. Exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): template shell, themed CSS, print rules, placeholders"
```

---

### Task 8: Template JS — decode, theme control, masthead — `static-verifiable`

**Depends on:** Task 7

Title and sources arrive base64 and are written with `textContent`, so no string interpolation reaches markup.

**Files:**
- Modify: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== template JS: decode and masthead =="
chk "decodeB64 helper present" "$(grep -c 'function decodeB64' "$S/template.html")" "1"
chk "title written with textContent" \
  "$(grep -c 'briefTitle").textContent = title' "$S/template.html")" "1"
chk "theme persisted to localStorage" \
  "$(grep -c "localStorage.setItem(\"brief-theme\"" "$S/template.html")" "1"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: three FAILs, exit 1.

- [ ] **Step 3: Replace the empty IIFE with the decode, theme and masthead sections**

In `assets/change-brief/template.html`, replace:

```html
<script>
(function(){
  "use strict";
})();
</script>
```

with:

```html
<script>
(function(){
  "use strict";

  function esc(s){
    return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;")
                    .replace(/>/g,"&gt;").replace(/"/g,"&quot;");
  }
  function decodeB64(b64){
    var clean = String(b64 || "").replace(/\s+/g, "");
    if (!clean) return "";
    var bin = atob(clean);
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder("utf-8").decode(bytes);
  }

  /* ---------- theme (pure CSS switch, no diagram re-render) ---------- */
  var root = document.documentElement;
  var mq = window.matchMedia("(prefers-color-scheme: dark)");
  var pref = localStorage.getItem("brief-theme") || "auto";
  function resolved(){ return pref === "auto" ? (mq.matches ? "dark" : "light") : pref; }
  function applyTheme(){
    root.setAttribute("data-theme", resolved());
    Array.prototype.forEach.call(document.querySelectorAll("[data-theme-set]"), function(b){
      b.setAttribute("aria-pressed", String(b.dataset.themeSet === pref));
    });
  }
  Array.prototype.forEach.call(document.querySelectorAll("[data-theme-set]"), function(b){
    b.addEventListener("click", function(){
      pref = b.dataset.themeSet;
      localStorage.setItem("brief-theme", pref);
      applyTheme();
    });
  });
  mq.addEventListener("change", function(){ if (pref === "auto") applyTheme(); });
  applyTheme();

  /* ---------- masthead (base64 in, textContent out: no injection path) ---------- */
  var title = decodeB64(document.body.dataset.title) || "Change Brief";
  document.getElementById("briefTitle").textContent = title;
  document.title = title + " — Change Brief";
  var stamps = document.getElementById("briefStamps");
  [ "generated " + (document.body.dataset.generated || "unknown"),
    decodeB64(document.body.dataset.sources) ]
    .filter(Boolean)
    .forEach(function(t){
      var s = document.createElement("span");
      s.className = "stamp";
      s.textContent = t;
      stamps.appendChild(s);
    });

  /* ---------- payload ---------- */
  var md;
  try { md = decodeB64(document.body.dataset.brief); }
  catch (e) { md = "## Payload decode failed\n\n`" + String(e) + "`"; }

  var content = document.getElementById("content");

  function banner(head, msg){
    var b = document.createElement("div");
    b.className = "integrity-banner";
    var s = document.createElement("strong"); s.textContent = head;
    b.appendChild(s);
    b.appendChild(document.createTextNode(msg));
    content.parentNode.insertBefore(b, content);
  }
})();
</script>
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: three PASSes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): payload decode, theme control, injection-free masthead"
```

---

### Task 9: Template JS — inertness — `static-verifiable`

**Depends on:** Task 8

The brief is opened by a persona with no repo and no context, often from an email attachment. Three independent escape hatches exist and all three must be closed. Escaping raw HTML alone is not enough: `![](https://host/px.gif)` still beacons the reader's IP and open time.

**Files:**
- Modify: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: five FAILs, exit 1.

- [ ] **Step 3: Add the inertness section**

In `assets/change-brief/template.html`, insert immediately after the `banner` function and before the closing `})();`:

```js
  /* The document must be inert. Three separate escape hatches exist and all
     three are closed here:
       - raw HTML in the payload  -> escaped, not executed
       - markdown images          -> remote URLs fetch on load; shown as a chip
       - markdown links           -> javascript:/data: hrefs execute on click
     Raw-HTML escaping alone is not enough: an `![](https://host/px.gif)` in a
     brief still beacons the reader's IP and open-time to that host. */
  /* Scheme-based, not prefix-based. A prefix allowlist that admits "./x" but
     not the equally common bare "BLOCKS.md" silently demotes valid links, and
     an allowlist is the wrong shape for the question anyway: what matters is
     whether a scheme is present and dangerous. Control characters and
     whitespace are stripped first — "java&#9;script:" is a live scheme. */
  function decodeEntities(s){
    /* A textarea decodes character references without executing anything.
       Needed because "java&#9;script:" is not a control character at the
       source level, but the browser decodes the entity to a tab and then
       strips it, reconstituting a live javascript: scheme. */
    var t = document.createElement("textarea");
    t.innerHTML = String(s || "");
    return t.value;
  }
  function safeHref(raw){
    // Backslashes are normalised to "/" BEFORE the check. For special schemes
    // (file: among them) the WHATWG URL parser treats "\" as "/", so "/\host"
    // is an equivalent spelling of "//host" and reaches the same remote host.
    var h = decodeEntities(raw).replace(/[\u0000-\u0020\u007f]/g, "").replace(/\\/g, "/");
    // "//host/x" has no scheme but is not document-relative: it resolves to
    // file://host/x, which on Windows is a UNC path and a click attempts an
    // SMB connection to an attacker-chosen host.
    if (/^\/\//.test(h)) return false;
    var m = h.match(/^([a-z][a-z0-9+.\-]*):/i);
    if (!m) return true;                              // no scheme: relative or fragment
    return /^(https?|mailto)$/i.test(m[1]);
  }
  if (typeof marked === "undefined" || typeof marked.use !== "function") {
    banner("Renderer unavailable",
      "marked.use is missing, so payload HTML could not be neutralised. Refusing to render.");
    return;
  }
  marked.use({ renderer: {
    html: function(token){
      var raw = (token && typeof token === "object") ? (token.raw || token.text || "") : token;
      return esc(raw);
    },
    image: function(token){
      var href = (token && typeof token === "object") ? token.href : arguments[0];
      var text = (token && typeof token === "object") ? (token.text || "") : (arguments[2] || "");
      if (/^data:image\//i.test(href || "")) {
        return '<img src="' + esc(href) + '" alt="' + esc(text) + '">';
      }
      return '<span class="img-chip"><b>image</b>' + esc(text || "untitled") +
             ' — ' + esc(href || "") + '</span>';
    },
    link: function(token){
      var href = (token && typeof token === "object") ? token.href : arguments[0];
      var text = (token && typeof token === "object") ? (token.text || "") : (arguments[2] || "");
      if (!safeHref(href)) return esc(text) + " (" + esc(href) + ")";
      return '<a href="' + esc(href) + '" rel="noopener noreferrer">' + esc(text) + "</a>";
    }
  } });

  content.innerHTML = marked.parse(md, { gfm:true, breaks:false });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: five PASSes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): inertness — escape HTML, chip remote images, scheme allowlist"
```

---

### Task 10: Template JS — structural integrity — `static-verifiable`

**Depends on:** Task 9

A source-side heading count cannot work: it requires a second CommonMark implementation, and every divergence between the two is either a false alarm or silent loss. `render.sh` always appends a sentinel-marked Plan heading, so its absence proves content was lost.

**Files:**
- Modify: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== template JS: structural integrity =="
chk "sentinel constant present" "$(grep -cF 'PLAN_MARK = "\u2060"' "$S/template.html")" "1"
chk "content-lost banner present" \
  "$(grep -c 'Content lost during rendering' "$S/template.html")" "1"
chk "render.sh warnings surface as banners" \
  "$(grep -c 'Source problem' "$S/template.html")" "1"
chk "no source-side heading count remains" \
  "$(grep -c 'data-headings' "$S/template.html")" "0"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: three FAILs (the fourth already passes), exit 1.

- [ ] **Step 3: Add the structural integrity section**

Append inside the IIFE, after `content.innerHTML = marked.parse(...)`:

```js
  /* Structural integrity, asserted against the DOM the reader actually sees.
     A source-side heading count cannot work: it requires a second CommonMark
     implementation, and every divergence between the two is either a false
     alarm or silent loss. render.sh always appends a sentinel-marked Plan
     heading, so its absence proves content was lost — by an unterminated
     comment, an unterminated fence, an HTML block, a front-matter misparse, or
     any cause nobody has thought of yet. */
  var PLAN_MARK = "\u2060";
  var planH2 = Array.prototype.filter.call(content.querySelectorAll("h2"), function(h){
    return h.textContent.indexOf(PLAN_MARK) !== -1;
  })[0];

  if (planH2) {
    planH2.textContent = planH2.textContent.replace(PLAN_MARK, "");
  } else {
    banner("Content lost during rendering",
      "The Plan section this brief always ends with did not survive parsing, so " +
      "an unknown amount of content is missing. Do not review from this page — " +
      "check the markdown source.");
  }

  if (planH2 && document.body.dataset.planState === "pending" &&
      !content.querySelector("blockquote, .callout")) {
    banner("Pending notice missing",
      "This brief was rendered before the plan was written, but the notice " +
      "saying so did not render. Treat the Plan section as unwritten.");
  }

  /* Warnings render.sh detected before parsing. */
  decodeB64(document.body.dataset.diag).split("\n").forEach(function(w){
    if (w.trim()) banner("Source problem", w.trim());
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: four PASSes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): prove truncation via sentinel survival, surface scanner warnings"
```

---

### Task 11: Template JS — callouts, badges, progress, mermaid extraction — `static-verifiable`

**Depends on:** Task 10

Clean heading text is captured into `data-toc` *before* badges and progress bars mutate the DOM, otherwise index entries read `Task 1: Render scriptstatic-verifiable`.

**Files:**
- Modify: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== template JS: callouts, badges, progress =="
chk "PENDING alert mapped" "$(grep -c 'PENDING:"pending"' "$S/template.html")" "1"
chk "pending label text" "$(grep -c 'Plan not yet written' "$S/template.html")" "1"
chk "data-toc capture present" "$(grep -c 'h.dataset.toc =' "$S/template.html")" "1"
chk "mermaid fences become boxes" \
  "$(grep -c 'code.language-mermaid' "$S/template.html")" "1"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: four FAILs, exit 1.

- [ ] **Step 3: Add the DOM decoration sections**

Append inside the IIFE, after the diagnostics banner loop:

```js
  /* ---------- mermaid fences -> placeholder boxes ---------- */
  Array.prototype.forEach.call(content.querySelectorAll("pre > code.language-mermaid"), function(code){
    var box = document.createElement("div");
    box.className = "mermaid-block";
    box.dataset.src = code.textContent;
    code.parentNode.replaceWith(box);
  });

  /* ---------- GitHub-style callouts (incl. PENDING) ---------- */
  var ALERTS = { NOTE:"note", WARNING:"warning", IMPORTANT:"important",
                 TIP:"tip", CAUTION:"important", PENDING:"pending" };
  var LABELS = { PENDING:"Plan not yet written" };
  Array.prototype.forEach.call(content.querySelectorAll("blockquote"), function(bq){
    /* firstElementChild, not querySelector("p"): the latter is descendant-
       scoped, so "> > [!WARNING]" hands the OUTER blockquote the INNER one's
       paragraph -- the outer converts and the inner's marker is sliced off.
       GitHub's rule: the marker must be the blockquote's own first line. */
    var first = bq.firstElementChild;
    if (!first || first.tagName !== "P") return;
    var m = first.innerHTML.match(/^\s*\[!([A-Z]+)\]\s*(<br\s*\/?>)?\s*/);
    if (!m || !ALERTS[m[1]]) return;
    first.innerHTML = first.innerHTML.slice(m[0].length);
    var div = document.createElement("div");
    div.className = "callout " + ALERTS[m[1]];
    var label = document.createElement("span");
    label.className = "callout-label";
    label.textContent = LABELS[m[1]] || m[1].toLowerCase();
    div.appendChild(label);
    while (bq.firstChild) div.appendChild(bq.firstChild);
    bq.replaceWith(div);
  });

  /* ---------- capture clean heading text BEFORE badges/progress mutate it ---------- */
  Array.prototype.forEach.call(content.querySelectorAll("h1, h2, h3"), function(h){
    h.dataset.toc = h.textContent.replace(/\s*[—–-]\s*(static-verifiable|browser-walk-only)\s*$/, "").trim();
  });

  function sectionNodes(h){
    var out = [], n = h.nextElementSibling;
    while (n && !/^H[1-3]$/.test(n.tagName)) { out.push(n); n = n.nextElementSibling; }
    return out;
  }

  /* ---------- walk-tag badges ---------- */
  Array.prototype.forEach.call(content.querySelectorAll("h2 code, h3 code"), function(c){
    var t = c.textContent.trim();
    if (t !== "browser-walk-only" && t !== "static-verifiable") return;
    var b = document.createElement("span");
    b.className = "badge " + (t === "browser-walk-only" ? "walk" : "static");
    b.textContent = t;
    var prev = c.previousSibling;
    if (prev && prev.nodeType === 3) prev.textContent = prev.textContent.replace(/\s*[—–-]\s*$/, "");
    c.replaceWith(b);
  });

  /* ---------- per-task checkbox progress ---------- */
  Array.prototype.forEach.call(content.querySelectorAll("h3"), function(h){
    var boxes = [];
    sectionNodes(h).forEach(function(n){
      boxes = boxes.concat(Array.prototype.slice.call(n.querySelectorAll('input[type=checkbox]')));
    });
    if (!boxes.length) return;
    var done = boxes.filter(function(b){ return b.checked; }).length;
    var p = document.createElement("span");
    p.className = "progress";
    var bar = document.createElement("span"); bar.className = "bar";
    var fill = document.createElement("span");
    /* floor: rounding renders 199/200 as a visually full bar. */
    fill.style.width = Math.floor(done / boxes.length * 100) + "%";
    bar.appendChild(fill);
    p.appendChild(bar);
    p.appendChild(document.createTextNode(done + "/" + boxes.length));
    h.appendChild(p);
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: four PASSes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): callouts, walk badges, per-task progress, mermaid extraction"
```

---

### Task 12: Template JS — task dependency graph — `static-verifiable`

**Depends on:** Task 11

The graph is scoped to the **plan region** — the siblings following the sentinel heading — not to the first task-shaped `h3` in the document. A spec that illustrates the plan format with its own `### Task 1: …` heading otherwise captures the anchor, putting the graph a document above the real tasks and emitting a duplicate node.

**Files:**
- Modify: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: every assertion in the three new blocks FAILs — all three blocks are new — exit 1.

- [ ] **Step 3: Add the dependency graph builder**

> The snippet below has been **regenerated from the shipped template by Task 15**, whose
> Step 3d edits land inside this mirrored slice. It therefore already carries
> `planRegionHeadings`, the `collected` flag and the "No tasks found" banner. That is
> `mirror_chk` working as intended — an un-regenerated snippet here would be a stale
> instruction, and nothing else in the suite can see that. See Task 15, Step 3g.

Insert inside the IIFE, immediately after the `sectionNodes` definition and before the walk-tag badges section:

```js
  /* ---------- task dependency graph, built from **Depends on:** ---------- */
  function buildDag(headings){
    /* Ids are normalised, not used raw. Zero-padding and sub-numbers both have
       to survive the round trip: "### Task 03:" and a "Depends on: Task 3"
       reference are otherwise different ids and the edge silently disappears,
       while "### Task 2.1:" and "### Task 2.2:" both collapse onto T2 because
       "." reads as the title separator. Driven against the vendored mermaid
       10.9.1, two node definitions sharing an id render as ONE node with the
       last label -- no error, no warning, a real task deleted and its edges
       misrouted onto the survivor. parseInt per dot-separated segment kills the
       padding; keeping the dotted number as the id keeps 2.1 and 2.2 apart. */
    function normId(raw){
      return String(raw).split(".").map(function(seg){
        return String(parseInt(seg, 10));
      }).join(".");
    }
    /* "." is not legal in a mermaid node name; the DISPLAY id keeps it. */
    function nodeName(id){ return "T" + id.replace(/\./g, "_"); }
    /* Ranges are expanded BEFORE the split, and the two changes are one change:
       adding dashes to the split alternation without this turns "Tasks 1–3"
       into ["Tasks 1", "3"], which draws edges from 1 and 3 and drops 2 without
       saying so — a quietly incomplete graph, which is strictly worse than the
       honest silence it replaces. Plain integers only: "Task 2.1-2.3" is not a
       range, and the (^|[^\d.]) guard is what keeps a dotted id's tail from
       being read as one endpoint. Bounded at 64 because a descending or absurd
       span is prose that happens to contain two numbers and a dash ("lines
       1-9999"), not a declaration, and inventing thousands of ids from it costs
       more than ignoring it; 64 is far wider than any plan this format targets. */
    function expandRanges(str){
      return str.replace(/(^|[^\d.])(\d+)\s*[–—-]\s*(\d+)(?![\d.])/g, function(all, pre, a, b){
        var lo = parseInt(a, 10), hi = parseInt(b, 10), out = [];
        if (hi < lo || hi - lo > 64) return all;
        for (var n = lo; n <= hi; n++) out.push(n);
        return pre + out.join(", ");
      });
    }
    var tasks = [], edges = [];
    headings.forEach(function(h){
      /* Task 11's toc capture is a guarded section: if it ever catches, the
         attribute is absent and h.dataset.toc.match throws. Fall back to the
         live heading text rather than losing this feature too. */
      var m = (h.dataset.toc || h.textContent).match(/^Task\s+(\d+(?:\.\d+)*)\s*[:.—-]?\s*(.*)$/i);
      if (!m) return;
      var id = normId(m[1]), label = (m[2] || "").trim() || ("Task " + id);
      /* Anchored to the end of the heading, the same shape the toc capture
         uses. A bare substring test paints "### Task 2: Document the
         browser-walk-only convention — static-verifiable" amber. */
      var walk = /\s*[—–-]\s*browser-walk-only\s*$/.test(h.textContent);
      tasks.push({ id:id, label:label, walk:walk });
      /* Anchored to the START of a paragraph, first declaration only, and
         "none" suppresses. A loose search over every node in the section
         harvests the string from prose and code fences alike — a step reading
         'add `Depends on: Task 3` to the template' fabricated a real edge.
         The HR stop closes the other end of the same leak: the last task's
         section runs to EOF, so a closing paragraph sitting after a "---" rule,
         which belongs to no task at all, was attributed to whichever task
         happened to come last. */
      var nodes = sectionNodes(h);
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].tagName === "HR") break;
        if (nodes[i].tagName !== "P") continue;
        var dm = (nodes[i].textContent || "").trim().match(/^Depends on:\s*(.*)$/i);
        if (!dm) continue;
        if (!/^none\b/i.test(dm[1].trim())) {
          /* Tokenised, never a digit harvest. Reading every number left in the
             sentence as a task id turns "Depends on: Task 1 (see section 4.2 of
             the spec)" into the real 1->N edge PLUS phantom 4->N and 2->N; on a
             plan that has a task 4 the phantom reverses the real 3->4 and draws
             a cycle the source never declared. known[] below only rescues
             numbers larger than the task count, so its protection is strongest
             on the two-task plans that do not need it and nil on the long ones
             this feature exists for. A token earns an edge only if the whole
             token is a task reference.

             Dashes are separators too, so "Task 11 — see the note" keeps its
             one real dependency instead of dropping it for the trailing prose.
             That is why expandRanges runs first: see its comment. */
          expandRanges(dm[1].replace(/\([^)]*\)/g, " "))
            .split(/\s*(?:,|;|\band\b|&|\+|[–—]|\s-\s)\s*/i)
            .forEach(function(tok){
              var t = tok.match(/^\s*(?:Tasks?\s*)?#?(\d+(?:\.\d+)*)\.?\s*$/i);
              if (!t) return;
              var d = normId(t[1]);
              if (d !== id) edges.push([d, id]);
            });
        }
        break;
      }
    });
    if (tasks.length < 2) return null;
    var known = {}, dup = null;
    tasks.forEach(function(t){ if (known[t.id] && !dup) dup = t.id; known[t.id] = true; });
    /* Suppress rather than mislead. Two headings on the same normalised number
       cannot be drawn without deleting one of them, and a graph that quietly
       drops a task while captioning itself as the plan's dependency graph is
       the exact failure class this file exists to refuse.

       Not redundant now that ids are normalised — normId is itself a source of
       collisions the raw text does not have. "### Task 2.1" and "### Task 2.01"
       are two distinct headings that both normalise to 2.1, and this check is
       the only thing standing between that and a silently deleted task. Do not
       delete it as dead code. */
    if (dup) return { src: null, dup: dup };
    var seen = {};
    edges = edges.filter(function(e){
      var k = e[0] + ">" + e[1];
      if (seen[k]) return false;            /* two declarations, one arrow */
      seen[k] = true;
      return known[e[0]] && known[e[1]];
    });
    var lines = ["flowchart LR"];
    tasks.forEach(function(t){
      lines.push('  ' + nodeName(t.id) + '["' + t.id + ' · ' + t.label.replace(/["]/g, "'") + '"]');
    });
    edges.forEach(function(e){ lines.push("  " + nodeName(e[0]) + " --> " + nodeName(e[1])); });
    var walks = tasks.filter(function(t){ return t.walk; }).map(function(t){ return nodeName(t.id); });
    if (walks.length){
      lines.push("  classDef walk fill:#b45309,stroke:#b45309,color:#fff");
      lines.push("  class " + walks.join(",") + " walk");
    }
    return { src: lines.join("\n"), edges: edges.length };
  }
  /* compareDocumentPosition, not the sibling chain: tasks nested inside a list,
     a blockquote, or a <details> are not siblings of the sentinel and yielded
     no graph at all, silently.

     Note what this costs. planTasks() guaranteed every heading it returned was
     a direct child of #content, and that invariant is gone: an h3 the markdown
     renderer nested inside an <li> now qualifies. Task 12 anchors the diagram
     and its caption on planH2 precisely because of this — anchoring on the
     first task's parent would bury both inside that list item. That anchoring
     must stay.

     A helper, not a section: like sectionNodes above it stays unwrapped at
     IIFE scope on purpose, since a guard() would scope the declaration to that
     callback and its caller would die under the wrong label. */
  function planRegionHeadings(){
    if (!planH2) return [];
    return Array.prototype.filter.call(content.querySelectorAll("h3"), function(h){
      return !!(planH2.compareDocumentPosition(h) & Node.DOCUMENT_POSITION_FOLLOWING);
    });
  }
  /* Declared here, at IIFE scope, and assigned inside the guard below — not
     declared inside it. Task 15 adds a sibling "No tasks found" banner that
     reads this binding; a var inside a guard callback is function-scoped to
     that callback and invisible to anything after it. Containment still holds:
     what can throw is the scan, and the scan is what the guard wraps. */
  var tasks = [];
  var collected = false;
  /* The same (h.dataset.toc || h.textContent) fallback the DAG builder uses,
     and this is where it has to be: this filter is the real gate. test()
     coerces a missing attribute to "undefined" without throwing, so a caught
     guard for the heading toc text makes every heading test false, tasks
     comes back empty, buildDag is never called, and the fallback inside it can
     never fire. */
  guard("dag: collect plan tasks", function(){
    tasks = planRegionHeadings().filter(function(h){
      return /^Task\s+\d+/i.test(h.dataset.toc || h.textContent);
    });
    collected = true;
  });
  /* Gated on `collected`, not on tasks.length alone. An empty `tasks` has two
     causes — the document genuinely has no task headings, or the guard above
     caught — and only the first is a fact about the source. Firing on the
     second prints a confident false claim about the reader's document with the
     task headings visible directly below the banner, which is exactly what the
     comment on that filter forbids. Guarded per the Tasks 9-14 containment
     doctrine: a bare top-level statement here throws uncaught and kills every
     section after it. */
  guard("dag: no tasks banner", function(){
    if (planH2 && collected && document.body.dataset.planState === "attached" && !tasks.length) {
      banner("No tasks found",
        "This brief was rendered with a plan attached, but no task headings were " +
        "found in the Plan section. The dependency graph is missing.");
    }
  });
  guard("dag: build and insert graph", function(){
    if (!tasks.length || !planH2) return;
    var dag = buildDag(tasks);
    if (!dag) return;
    /* A suppressed graph is a banner, not a caption. .dag-caption is a faint
       12px mono line with a negative top margin, shaped to tuck under a diagram;
       with no diagram above it, the most important message this feature emits
       renders as a subtitle to the Plan heading and its margin decorates
       nothing. banner() is the surface this file already has for "something
       about what you are reading is not what it appears", and a suppressed
       graph is squarely that. */
    if (!dag.src) {
      banner("Dependency graph suppressed",
        "Two task headings carry the number " + dag.dup + ", so any graph drawn " +
        "from them would silently drop one.");
      return;
    }
    var cap = document.createElement("div");
    cap.className = "dag-caption";
    /* Describes the PARSE, never the source. A caption announcing that the
       tasks have no dependencies is a claim about the DOCUMENT, and it is flatly
       false whenever a plan declares its dependencies as list items or table
       cells — shapes the P-only scan above deliberately skips so that fixture
       fences inside a plan cannot fabricate edges. Saying what was recognised
       is true in every case and costs nothing. */
    cap.textContent = dag.edges
      ? "task dependency graph — derived from declared Depends on:"
      : "no Depends on: declarations were recognised";
    /* Anchored to planH2, not to the first task heading's parent node. Those
       are the same element only while planTasks() returns siblings of the
       sentinel; Task 15 replaces it with a compareDocumentPosition filter that
       also matches an h3 the markdown renderer nested inside an <li>, and the
       diagram and its caption would then be buried inside that list item. Box
       first, caption second: .dag-caption pulls itself up under the diagram
       with a negative top margin. */
    var anchor = planH2.nextSibling;
    var box = document.createElement("div");
    box.className = "mermaid-block";
    box.dataset.src = dag.src;
    planH2.parentNode.insertBefore(box, anchor);
    planH2.parentNode.insertBefore(cap, anchor);
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: all three new blocks PASS and the suite reports 195 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): derive task graph from Depends on, scoped to the plan region"
```

---

### Task 13: Template JS — dual-theme mermaid rendering — `browser-walk-only`

**Depends on:** Task 11

Mermaid v10 is async-only: the v8/v9 callback form produces no output and no exception, leaving every diagram blank. Each fence renders twice up front so theme switching is a pure CSS toggle and print can select the light variant synchronously.

`flowchart: { htmlLabels: false }` is not cosmetic and is not optional — and it is not sufficient on its own either; the `secure` list below is what turns it into a control. What follows separates what has been observed from what has only been inferred, because a later reader will take whatever this paragraph asserts as verified — and that boundary has already moved twice.

**Observed**, driven against the vendored 10.9.1 bundle at `securityLevel:"strict"`:

- Mermaid v10 builds flowchart labels as *markup*, not as text. A `<b>x</b>` label comes back as a real `<b>` element inside a `<foreignObject>`.
- A heading carrying `<img src=https://evil.example.invalid/x.png>` produces a **real `<img>` element, attached to the live document, holding that exact URL**. It is reachable by polling the DOM mid-render: the render promise hangs afterwards, but the element is already in the document by then. Counted: two `<foreignObject>` elements, one `<img>`.
- **DOMPurify runs, and does not remove it.** The sanitiser is not being bypassed, and its allowlist has been exercised rather than read: `<svg onload=alert(1)>` comes back as `<svg></svg>` — handler stripped, element kept — and the `<img src=…>` survives that same pass.
- With `flowchart: { htmlLabels: false }`, the same labels produce zero `<img>` elements, zero `<foreignObject>` elements, and the render settles instead of hanging — **provided the payload cannot put the setting back.** It could.
- **`initialize()` is not, on its own, a control over untrusted content.** Mermaid 10.9.1 protects exactly the keys on its `secure` list, read out of the vendored bundle as `["secure","securityLevel","startOnLoad","maxTextSize","maxEdges"]`. `flowchart.htmlLabels` and `theme` are absent from it, and the sanitiser applies that list recursively at every depth, so a payload-supplied `%%{init: {"flowchart": {"htmlLabels": true}}}%%` directive overrides whatever `initialize` set. Reproduced end-to-end on real `render.sh` output by two independent routes: a mermaid fence in the payload, and a task heading reaching mermaid through Task 12's generated node label — where `label.replace(/["]/g, "'")` fails to disarm it, because mermaid's directive parser accepts single quotes. Each produced a live `<img src=…>` attached to the document, two `<foreignObject>` elements, and a render that never settled.
- **`securityLevel` *is* on that list**, so a `"securityLevel":"loose"` directive is refused and DOMPurify still strips `onerror`. This is a beacon plus denial-of-render, not script execution.
- **`themeCSS` is the same beacon with a lower bar, and it survived the round that closed those two.** It is in the default config, so it passes the key allowlist; it is not on the `secure` list; and its only value check is a brace-balance test, which text containing no braces passes trivially. It is then concatenated **verbatim, at top level, outside any block** into the `<style>` that DOMPurify keeps. Reproduced live and `isConnected` by all three routes — payload fence, YAML frontmatter (which funnels through the same `addDirective`), and a task heading through the generated DAG label:
  ```
  @font-face{font-family:pwn;src:url(https://evil.example.invalid/p.woff2);}
  ```
  It needs neither `htmlLabels` nor a `<foreignObject>`, which is exactly why it survived a round that was framed as "are these two routes closed?" rather than "what is the class?".
- `fontFamily` reaches the same stylesheet but lands inside a `:root { }` block, and the brace-balance check stops it escaping — verified by attempting exactly that escape. It is pinned anyway, because it is the same sink. **`altFontFamily` is a different case and should not be mistaken for a live control:** it is absent from mermaid's default config, so it is not in the key allowlist at all and every directive carrying it is deleted before the `secure` list is ever consulted. Pinning it is harmless belt-and-braces against a future default gaining the key; nothing depends on it today.
- **What the class is, checked rather than assumed.** The emitted `<style>` is assembled from exactly three config keys — `themeCSS`, `fontFamily`, `altFontFamily` — plus `themeVariables.*`, which is charset-restricted to `/^[\d "#%(),.;A-Za-z]+$/` and so cannot spell `:` or `/`. A battery across flowchart, sequence, ER, C4, requirement, sankey, gantt, journey and gitGraph found nothing else reaching a stylesheet. Six keys do put payload text into *attributes* — `sankey.linkColor` and `er.stroke` as `stroke="url(remote)"`, `c4.person_bg_color` as `rect[fill]`, `c4.person_border_color` as `rect[stroke]`, the diagram-specific `*FontFamily` keys as `font-family="…"`, `sequence.messageAlign` as `text[text-anchor]`, and `gantt.useWidth` as `svg[viewBox]` — but at-rules are inert in an attribute value and browsers do not fetch external SVG paint servers, so none is a beacon. Directives were also checked for leaking between fences and between passes: they do not.
- Pinning `"htmlLabels"`, `"theme"`, `"themeCSS"`, `"fontFamily"` and `"altFontFamily"` closes every route found: zero `<img>`, zero `<foreignObject>`, zero live `<style>` carrying the payload host, with every diagram still rendering in both themes at the correct per-theme colours (`#333` light, `#ccc` dark — confirming the list constrains directives only, not `initialize`'s own config, and that `fontFamily:"inherit"` still applies). `"theme"` earns its place independently: a `%%{init:{"theme":"dark"}}%%` fence makes the **light** slot paint with dark-theme colours, and print forces `.d-light`.

**Inferred, and still unconfirmed: only the fetch itself** — that the browser, having been handed a live `<img src>` pointing at a payload-supplied URL, then requests it. Everything up to and including that element in the document is observed; the request is not.

**Do not read the harness's silence as evidence either way.** A request interceptor recorded zero attempts — but so did the control: a plain `<img>` inserted straight into `document.body` also produced zero. jsdom does not load images here at all, so that harness is structurally blind and proves nothing in either direction. "Zero requests observed" under it is not a safety result; it is a measurement that could not have detected the thing it was pointed at. **Walk case 10 is the arbiter**, and its result belongs back in this paragraph.

The fix does not wait on that confirmation, and stays right even if the fetch never fires: a document whose entire premise is inertness must not hand un-escaped payload text to a renderer that constructs live elements out of it. That is also a door Task 9 never covered — Task 9 escapes payload HTML at parse time so the DOM holds the literal string, and Tasks 11 and 12 are the first paths that hand that literal *back* to a renderer which un-escapes it. Setting it in `initialize`, **and pinning it there with the `secure` list**, covers Task 11's fence extraction and Task 12's derived graph in one place.

One more consequence, recorded because the renderer below walks its boxes sequentially: a box whose render promise never settles stalls every later diagram and both of its theme passes. The `<img>`-bearing label above is exactly that case. The *dependency* is observed — `htmlLabels:true` with a plain label completes in 102ms, and only the image-bearing label hangs — but the **mechanism is inferred, not observed**: the bundle contains no image-load await on the flowchart path (zero `onload` handlers; its sole `new Image` belongs to cytoscape), so "the constructed image element is awaiting a load that never arrives" remains a plausible story rather than a traced one.

That is not a hypothetical waiting on a future change: until the `secure` list landed, a payload could reach it on purpose. Measured on a four-diagram brief whose first fence carried the directive, **0 of 4 diagrams rendered in light and 0 of 4 in dark** — four empty bordered boxes, no error box, console silent.

**The reason is worse than "the chain is sequential", and an earlier draft of this paragraph got it wrong.** Mermaid serialises *every* `parse` and `render` through one internal queue drained by `await task()`. A task that never settles is abandoned, not cancelled, so it pins that queue permanently: after one stall nothing can render again, in either theme, for the life of the page. Traced against the vendored bundle — with render #1 hung, a completely clean diagram's parse #2 is still pending at 3s.

Three things follow, and each is load-bearing:

- **Race `parse` as well as `render`.** They share the queue, so an un-raced `parse` is a path along which our own chain never terminates. Racing only `render`, as an earlier version did, converts a silent stall into one error card *plus a still-stalled document*: measured end-to-end on real `render.sh` output with a genuine mermaid stall, one error card at 8.0s and then `light=0 dark=0`, marker never set, **still hung at 62s**.
- **Probe before latching, then short-circuit.** "No later box can succeed" is true of a pinned queue and false of the other thing a timeout looks like from outside: a legitimately slow render, where the queue is healthy and every later box would have been fine. Latching on the first timeout turns that per-box false positive into a document-wide one — measured against a box completing at 9s under the real 8s budget, an unconditional latch produced **four error cards and 0 of 4 diagrams in both themes**, where leaving it alone would have cost one card and kept three diagrams. So the first timeout does not latch, it probes: the next box is attempted on a 2s budget. If it renders, the queue was never wedged and full budgets resume — measured, **one error card and 3 of 4 diagrams in both themes at 9.2s**. If it times out too, the queue really is pinned and the latch fires, short-circuiting the remainder — measured on a genuine mermaid wedge, **10.0s** with the probe box reporting `Parse timed out after 2000ms`, which is the queue mechanic showing through: its parse never ran because it was sitting behind the abandoned task. The probe costs 2s on a real wedge and saves the document on a false positive; waiting a full budget per box instead would be 32s of dead time on four boxes.
- **Interleave the two theme passes per box** — light then dark for box 0, then box 1, and so on — rather than sweeping all boxes in light and then all in dark. With the wedge permanent this is not a micro-optimisation. Under two sweeping passes a stall partway through leaves every earlier box holding a light render and no dark one, and in dark theme the CSS hides `.d-light` and finds no `.d-dark`, so **a dark-theme reader gets blank cards for diagrams that rendered perfectly**. Measured on a four-diagram brief stalling at the third fence: sweeping passes give `light=2 dark=0`, interleaved gives `light=2 dark=2`.

Interleaving was **declined in an earlier round on a reason that was simply wrong** — that the race already fixed the stall outright, so interleaving would only shrink the blast radius. The race does not fix the stall, so blast radius is the whole question. It was then weighed on its own merits and adopted: it costs one extra `mermaid.initialize` per box per theme, measured at 0.47ms a call (about 5ms on a six-diagram brief); it does not affect print, which forces `.d-light` and sees the same set of light renders either way; and it does not affect walk case 11's duplicate-id question, because a fragment reference resolves to the first match in document order, which is box 0's *light* marker under both orderings.

Belt and braces on top of all three: a run-level deadline marks the run regardless, so `data-diagrams` is always set and a harness waiting on it can never hang. The marker carries four values — `done`, `failed`, `stalled`, `unavailable` — because four outcomes genuinely differ. Three of them mean the run ended; **`stalled` does not.** It means only "had not ended within 20s", which is a verdict about the deadline rather than about the run: because the first write wins and is never overwritten, a document whose renders eventually complete after the deadline keeps `stalled` while going on to show every diagram. That is deliberate — a marker that flapped from `stalled` to `done` would be worse than one that is occasionally pessimistic — but it means `stalled` should be read as "gave up waiting", not as "failed".

**Files:**
- Modify: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
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
# NOTE FOR TASK 14: the stop marker below is the IIFE's closing "})();" only
# because this renderer is currently the last section in the file. Task 14
# appends after it and must retarget the stop marker to Task 14's own header
# comment ('  /* ---------- build TOC ---------- */'). It will fail loudly, not
# silently, if that is forgotten.
MMD_HEAD='  /* ---------- mermaid: v10 async contract, both themes rendered up front ---------- */'
mirror_chk "Task 13's plan snippet is byte-identical to the shipped template" \
  "$MMD_HEAD" "$S/template.html" "$MMD_HEAD" '})();'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: thirty-two FAILs, exit 1. (Thirty-two of the thirty-three; "no v8/v9 callback form" expects a count of zero and so passes before the renderer exists at all.)

- [ ] **Step 3: Add the dual-pass renderer**

Append inside the IIFE, after the per-task progress section:

```js
  /* ---------- mermaid: v10 async contract, both themes rendered up front ---------- */
  var seq = 0;

  /* Mermaid serialises EVERY parse and render through one internal queue, drained
     by `await task()`. A task that never settles is abandoned, not cancelled, so
     it pins that queue permanently: after one stall nothing can render again, in
     either theme. Traced against the vendored bundle — with render #1 hung, a
     completely clean diagram's parse #2 is still pending at 3s.

     Two things follow, and both are structural rather than cautionary:

     1. Racing only `render` is not enough. `parse` goes through the same queue,
        so an un-raced parse is a path along which our own chain never terminates.
        Both are raced.
     2. Once one box has timed out, no later box can succeed — but only if the
        queue really is wedged. A timeout is also what a legitimately slow render
        looks like from outside, and there the queue is healthy and every later
        box would have rendered fine. Latching unconditionally on the first
        timeout turns that per-box false positive into a document-wide one:
        measured against a box that completes at 9s, an unconditional latch gave
        4 error cards and 0 of 4 diagrams in both themes, where doing nothing
        would have cost 1 error card and kept 3 good diagrams.

        So the first timeout does not latch, it PROBES: the next box is attempted
        on a short budget instead of the full one. If it renders, the queue was
        never wedged, the first timeout was a false positive, and full budgets
        resume for the rest of the document. If it times out too, the queue is
        genuinely pinned and `wedged` latches, short-circuiting every remaining
        box. Costs 2s on top of a real wedge; saves the whole document on a false
        positive. Waiting a full budget per box instead would be 32s of dead time
        on a four-box document.

        The probe is safe against the mechanics it is diagnosing. On a real wedge
        its parse simply queues behind the abandoned task and never runs, so it
        times out on its own budget rather than hanging the accounting; adding one
        more pending task to an already-pinned loop changes nothing observable. On
        a false positive the slow task is still draining, and the probe runs the
        moment it finishes — which is why the probe budget is also the window
        within which a false positive can still be rescued.

     8000ms is chosen against measurement. A typical diagram in this format
     settles in 9-32ms and a deliberately oversized 121-node flowchart, far larger
     than any brief produces, in 217ms; 8s is ~36x that worst case, so a slow or
     throttled machine cannot false-positive and destroy a good diagram. 2000ms
     for the probe is the same reasoning at a tighter ratio — ~9x that oversized
     worst case — because it is pure dead time on a real wedge and only has to be
     long enough to tell a working queue from a pinned one. Note both are layout
     budgets, not network ones: a payload can put a remote url() into the emitted
     stylesheet only through the config keys the `secure` list below pins, and a
     font or image fetch does not block the render promise anyway. */
  var wedged = false;
  var probing = false;
  var RENDER_TIMEOUT_MS = 8000;
  var PROBE_TIMEOUT_MS = 2000;
  function raceQueue(p, what){
    /* Fixed at call time: the budget this attempt is judged on cannot change
       underneath it if another box flips the flag. */
    var budget = probing ? PROBE_TIMEOUT_MS : RENDER_TIMEOUT_MS;
    return new Promise(function(resolve, reject){
      /* Rejects, never resolves. A timeout that resolved would hand the success
         branch an undefined result and leave an empty slot behind with no error
         card and no console line — the silent failure this section refuses. */
      var timer = setTimeout(function(){
        if (probing) wedged = true;   /* the probe timed out too: really pinned */
        else probing = true;          /* first timeout: diagnose before latching */
        reject(new Error(what + " timed out after " + budget + "ms"));
      }, budget);
      Promise.resolve(p).then(
        function(v){
          clearTimeout(timer);
          /* Anything settling proves the queue drains, which retires the probe
             and restores full budgets for the rest of the document. */
          probing = false;
          resolve(v);
        },
        function(e){ clearTimeout(timer); reject(e); }
      );
    });
  }

  /* Both themes for ONE box before moving to the next, rather than one theme
     across every box before starting the other. That ordering is load-bearing
     now that the queue wedge above is known to be permanent: with two sweeping
     passes, a stall partway through leaves every earlier box holding a light
     render and no dark one, and in dark theme CSS hides .d-light and finds no
     .d-dark — so a reader in dark mode gets blank cards for diagrams that
     rendered perfectly. Interleaved, every box before the stall is complete in
     both themes and only the stalled box and its successors degrade.

     It is not free and it is not neutral in every direction, so both were
     checked: it costs one extra mermaid.initialize per box per theme, measured
     at 0.47ms a call — about 5ms on a six-diagram brief. It does not affect
     print, which forces .d-light and sees the same set of light renders either
     way. And it does not affect the duplicate-unnamespaced-id question in walk
     case 11: a fragment reference resolves to the first match in document order,
     which is box 0's LIGHT marker under both orderings, since both begin with
     that box's light render. */
  var PASSES = [{ theme:"default", cls:"d-light" }, { theme:"dark", cls:"d-dark" }];

  function renderBox(box){
    var src = box.dataset.src;
    return PASSES.reduce(function(chain, pass){
      return chain.then(function(){
        /* An earlier pass failed and turned this box into an error card, which
           also dropped its data-src. Nothing left for this pass to do. */
        if (box.classList.contains("mermaid-error")) return;
        var id = "mmd-" + (seq++);
        return Promise.resolve()
          .then(function(){
            if (wedged) throw new Error("Skipped: an earlier diagram timed out and mermaid's render queue does not recover");
            mermaid.initialize({
              startOnLoad:false, securityLevel:"strict",
              /* initialize() is not, on its own, a control over untrusted
                 content. Mermaid 10.9.1 lets a %%{init: ...}%% directive — or an
                 equivalent YAML frontmatter block, which funnels through the same
                 addDirective — override any config key absent from the `secure`
                 list, and its stock list omits every key this file depends on.
                 The sanitiser walks a directive recursively at every depth and
                 matches leaf names exactly, so naming the leaf key is enough and
                 covers both syntaxes.

                 themeCSS is the sharpest of them: it is concatenated verbatim
                 into the emitted <style>, at top level, outside any block. Its
                 only check is a brace-balance test, which zero braces trivially
                 pass, so a payload can add an @font-face plus a rule that uses it
                 and the browser fetches the font from a host of its choosing.
                 fontFamily and altFontFamily reach the same stylesheet but land
                 inside a :root{ } block that the brace test stops them escaping.
                 htmlLabels reaches markup; theme repaints the LIGHT slot in dark
                 colours, which print then reproduces because print forces
                 .d-light. Every one of these was reproduced on real render.sh
                 output before being pinned here, by fence, by frontmatter, and
                 through Task 12's generated node label. */
              secure:["secure","securityLevel","startOnLoad","maxTextSize","maxEdges","htmlLabels","theme","themeCSS","fontFamily","altFontFamily"],
              /* Labels as SVG text, not innerHTML. See this task's preamble: at
                 strict, v10 still inserts flowchart labels as HTML and DOMPurify
                 keeps <img>, so an image tag in a task heading fires a real
                 network request out of a file whose whole premise is inertness. */
              flowchart:{ htmlLabels:false },
              theme: pass.theme, fontFamily:"inherit"
            });
            return raceQueue(mermaid.parse(src), "Parse");
          })
          .then(function(){ return raceQueue(mermaid.render(id, src), "Render"); })
          .then(function(res){
            var slot = document.createElement("div");
            slot.className = pass.cls;
            slot.innerHTML = res.svg;
            box.appendChild(slot);
          })
          .catch(function(err){
            /* Before any early return, so it runs on every failure path.
               Mermaid removes its temp container only on the success path: both
               failure exits throw with it still attached to <body>, where it
               shows mermaid's own error graphic outside .shell, unclassed and
               with no rule that hides it, in both themes and in print. Its only
               other cleanup is a later render reusing the same id, and seq is
               monotonic — which it must stay, since a reused id would also make
               v10's opening getElementById(id) removal tear the previous pass's
               injected <svg> back out of the box. */
            ["d" + id, "i" + id].forEach(function(orphan){
              var n = document.getElementById(orphan);
              if (n && n.parentNode) n.parentNode.removeChild(n);
            });
            /* Never destroy a pass that already succeeded. The two passes mutate
               one container; a dark-pass failure would otherwise replace a
               perfectly good light render with an error card — and print, which
               forces .d-light, would show the error. */
            if (box.querySelector(".d-light svg")) {
              /* ...but say so. Keeping the good render is right; keeping it
                 silently is not. This was the one path in the section that
                 produced neither a DOM signal nor a console line: a box that is a
                 correct diagram in light and an empty card in dark, with nothing
                 anywhere to explain the difference. */
              warn("mermaid: " + pass.cls + " pass for an already-rendered diagram", err);
              return;
            }
            box.className = "mermaid-error";
            box.removeAttribute("data-src");
            box.innerHTML =
              '<div class="err-head">Diagram failed to render</div>' +
              '<div class="err-msg">' + esc(err && err.message ? err.message : String(err)) + '</div>' +
              '<pre><code>' + esc(src) + '</code></pre>';
          });
      });
    }, Promise.resolve());
  }

  /* Completion marker for the walk harness: a waitForSelector on this beats a
     fixed waitForTimeout, and it is the only thing that can tell "slow" apart
     from "stalled". First writer wins, so the run-level deadline below cannot
     overwrite a real verdict and a late completion cannot overwrite the
     deadline's — the attribute never flaps, and a harness that reads it once has
     a stable answer. Four values, because four things genuinely differ: the run
     finished (with or without error cards); it died; it never finished at all;
     or mermaid was not on the page, which is not a completed run but a page of
     empty boxes. */
  function markRun(state){
    if (!root.hasAttribute("data-diagrams")) root.setAttribute("data-diagrams", state);
  }
  /* Belt and braces, and deliberately so: wedge detection above already bounds a
     stalled run to one timeout, but this section has twice been certain a class
     of hang was closed and been wrong. 20s is comfortably past the slowest
     legitimate run measurable here (a twenty-diagram brief of oversized graphs is
     ~8.7s, and a wedged one ~8.1s) and comfortably inside the 30s the browser
     harness waits, so the page always answers before the harness gives up. */
  var RUN_DEADLINE_MS = 20000;
  var runDeadline = setTimeout(function(){ markRun("stalled"); }, RUN_DEADLINE_MS);

  /* guard() covers the synchronous kick-off — the querySelectorAll and the reduce
     that builds the chain. Everything after the first tick, including every
     mermaid.initialize (which now runs inside a .then, per box and per theme), is
     a promise rejection that guard() structurally cannot see; the terminal .catch
     is what covers those. Without it a failure there is an unhandled rejection:
     no label, no warn(), nothing attributable to this file. */
  var diagramsStarted = false;
  guard("mermaid: start dual-theme render", function(){
    if (typeof mermaid === "undefined") {
      markRun("unavailable");
      clearTimeout(runDeadline);
      diagramsStarted = true;
      return;
    }
    Array.prototype.slice.call(document.querySelectorAll("[data-src]"))
      .reduce(function(chain, box){
        return chain.then(function(){ return renderBox(box); });
      }, Promise.resolve())
      .then(function(){ markRun("done"); })
      .catch(function(e){ warn("mermaid: dual-theme render chain", e); markRun("failed"); })
      .then(function(){ clearTimeout(runDeadline); });
    diagramsStarted = true;
  });
  /* The third state, found by measurement rather than reasoning: when guard()
     catches a synchronous throw the chain never starts, so neither .then nor
     .catch above can ever run and no marker is set. Observed at 63s with the
     attribute still absent — a harness waiting on [data-diagrams] hangs forever
     on the one path that is already a hard failure. Mark it here, synchronously. */
  if (!diagramsStarted) { markRun("failed"); clearTimeout(runDeadline); }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: all thirty-three new assertions PASS and the suite reports 228 passed, 0 failed. Visual confirmation is **walk cases 2, 4, 5, 10 and 11** — the static test proves the API contract, not that diagrams are legible.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): dual-theme mermaid rendering on the v10 async contract"
```

---

### Task 14: Template JS — index, scrollspy, mobile sidebar — `browser-walk-only`

**Depends on:** Task 12

Task headings attach to the Plan group by **region**, not by heading adjacency. Nesting `h3`s under "whichever `h2` came last" is why the plan's tasks were stolen in five consecutive review rounds — by an unnested `h3`, a stray `h1`, a demoted `h2`, and a setext `h2` manufactured from YAML front matter. Each fix removed one trigger and left the mechanism.

**Files:**
- Modify: `assets/change-brief/template.html`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

**Also retarget Task 13's `mirror_chk` stop marker in the same commit.** It is currently `'})();'`, which was correct only while the mermaid renderer was the last section in the file; this task appends after it, so the marker must become `'  /* ---------- build TOC ---------- */'`. The suite fails loudly rather than silently if this is missed, but it fails as a puzzling 100-line diff on Task 13's mirror, not as anything naming this task.

```bash
echo "== template JS: index =="
chk "index built from h2/h3 only" \
  "$(grep -c 'content.querySelectorAll("h2, h3")' "$S/template.html")" "2"
chk "tasks attach by document position" \
  "$(grep -c 'DOCUMENT_POSITION_FOLLOWING' "$S/template.html")" "1"
chk "scrollspy observer present" "$(grep -c 'IntersectionObserver' "$S/template.html")" "1"
chk "mobile sidebar toggle wired" "$(grep -c 'sbToggle' "$S/template.html")" "2"

# Ids are payload-derived and the document holds ids slug() did not generate:
# the shell's own, which exist by the time this runs, and the ~54 the dual-theme
# diagram pass injects, which do not exist yet and no lookup can see. One
# unconditional prefix answers both populations, and it is the whole defence
# against the second -- so it is pinned as a fixed string, byte for byte.
# Dropping the prefix, or making it conditional again, fails here.
chk "every heading id is prefixed unconditionally, so none can land in the diagram namespace" \
  "$(grep -cF 'var base = "h-" + (s.toLowerCase().replace(/[^\w\s-]/g,"").trim().replace(/\s+/g,"-") || "section");' "$S/template.html")" "1"
# Fixed string, so ADDING a clause back into the condition fails here -- which a
# grep for the loop's existence would not catch. A pattern tested against a loop
# CANDIDATE rather than against base can be non-terminating, because the
# candidate is what the body rewrites, and guard() catches throws, not hangs.
# What the condition is allowed to test is exactly what bounds it: `used` and
# the document are finite and neither grows inside the body.
chk "the retry condition tests only used and the document, so it is bounded" \
  "$(grep -cF 'while (used[id] || document.getElementById(id)) {' "$S/template.html")" "1"
# Belt, not the guard. It greps one literal token, so a pattern applied to
# `base + "-" + n` -- the same defect spelled differently -- sails past it. The
# fixed-string pin on the while condition above is what actually holds the line;
# this catches only the spelling that shipped once and was reverted.
chk "no pattern is tested against the loop candidate by name" \
  "$(grep -c 'test(id)' "$S/template.html")" "0"
# Defence in depth, not the fix, and the label says so because the measurement
# does: under the retry loop above, a plain {} and no map at all both produce
# byte-identical output. Object.create(null) removes a class of surprise the
# loop already happens to cover. Anchored at indent 2, like the sectionNodes
# pin: an unanchored grep still matches after the declaration is re-nested.
chk "slug's id map is prototype-free (defence in depth; the retry loop is the fix)" \
  "$(grep -c '^  var used = Object.create(null);$' "$S/template.html")" "1"
# Presence pin, and the honest scope is that no grep can see a loop advance.
# Termination is not proven here, and was never proven in jsdom either -- an
# earlier wording claiming so was wrong, and the loop it described did not in
# fact terminate. It follows instead from the condition pinned above: `used` and
# the document are finite, neither grows inside the body, and each turn proposes
# a distinct candidate, so a free one is reached in at most one turn more than
# there are ids already taken. This pins the increment that argument assumes.
chk "the retry loop advances its candidate each turn" \
  "$(grep -cF 'n++; id = base + "-" + n;' "$S/template.html")" "1"
# Expects zero, so it passes before the fix exists; it is here to catch the old
# form being restored alongside the new one, where the counter would run again
# and silently reintroduce the "Foo"/"Foo"/"Foo 2" collision.
chk "the per-base counter form, whose own output collided with real headings, is gone" \
  "$(grep -c 'used\[base\] = (used\[base\] || 0) + 1' "$S/template.html")" "0"

# rootMargin shrinks the observer root to the top 30% of the viewport, so for
# most of a section's scroll NOTHING is in the band -- and any heading with less
# than 0.7 of a viewport of content after it can never enter it at all. Without
# the early return the callback clears every active class and adds none, so the
# index goes blank through the body of every section and stays blank on the last
# one forever. Pinned on the RESOLUTION line rather than on the return, because
# that is what makes the stickiness total: it funnels both blank paths -- no
# heading in the band, and a heading that has no index entry to move the
# highlight to -- through one guard. A `first`-only test passes this file's
# other checks while still going blank on the second path.
chk "the scrollspy keeps its last highlight whenever there is no entry to move it to" \
  "$(grep -cF 'var a = first && links[first.id];' "$S/template.html")" "1"
# Order is the entire claim. The grep above still passes with the return moved
# below the clear loop -- where it would run after every class had already been
# stripped, restoring exactly the blank index it exists to prevent.
sticky_ln=$(grep -n 'if (!a) return;' "$S/template.html" | head -1 | cut -d: -f1)
clear_ln=$(grep -n 'links\[k\].classList.remove("active")' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$sticky_ln" ] && [ -n "$clear_ln" ] && [ "$sticky_ln" -lt "$clear_ln" ]; then
  ok "the sticky return runs before the clear loop, not after it"
else
  no "the sticky return runs before the clear loop, not after it" \
     "return=[${sticky_ln:-missing}] clear=[${clear_ln:-missing}]"
fi

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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: nineteen FAILs, exit 1 — measured against the pre-task template, not counted off the fence. Twenty-one assertions are appended and one more is retargeted; two of the twenty-one expect a count of zero ("no pattern is tested against the loop candidate by name" and "no section follows the mobile sidebar") and so pass before the code they guard exists, and Task 13's retargeted mirror fails here because its new stop marker is not in the template yet.

- [ ] **Step 3: Add the index, scrollspy and mobile sidebar**

Append inside the IIFE, after the mermaid renderer:

```js
  /* ---------- build TOC ---------- */
  /* These declarations stay at IIFE scope, deliberately outside the guard()
     below: `toc` is read by all three sections this task adds, and a guard()
     wrapper would scope the declaration to its own callback, leaving the
     scrollspy and the sidebar dead with a ReferenceError reported under
     someone else's label -- the sectionNodes precedent above. */
  /* Ids are payload-derived, and the document already holds ids this function
     did not generate. Two populations, and they need different answers:

     Ids that exist BY NOW -- the shell's own. A heading titled "Sidebar" or
     "Toc" used to take one, so its index link scrolled to the aside or to the
     nav instead of to the heading. Measured, not supposed.

     Ids that do not exist yet. This section is synchronous and the diagram
     chain is still in flight, so not one of the ~54 ids the dual-theme render
     injects exists when this runs, and no lookup can see them. Sixteen of them
     are literals in the vendored bundle, and because base is lowercased, eight
     are reachable from a heading: arrowend, arrowhead, crosshead, filled-head,
     sequencenumber, clock, computer and database -- three of which are
     plausible section names in a real spec. Colliding with one gives an index
     link that resolves into <defs>, unrendered and zero-size. Colliding with a
     box id was worse: render() opens by removing the elements whose ids are the
     box id and that id prefixed with d and with i, so the heading itself was
     DELETED from the document on the SUCCESS path, with no error card and no
     console line.

     One unconditional prefix answers both, and answers the second population --
     the one nothing can look up -- as completely as the first. Every id the
     library emits either has its own prefix or is one of those literals; none
     can begin "h-". It is not airtight, and the honest limit is worth stating:
     the bundle also emits payload-derived ids through attr("id", node.id)
     forms, so a deliberately hostile diagram node named "h-something" could
     still collide. What it eliminates is every accidental collision and every
     literal one. Task 17's deadAnchors probe is the backstop for the rest --
     it asserts the spec-level property (every index entry resolves to its own
     heading) in a real browser, after the diagrams have landed, rather than
     chasing a version-coupled vocabulary here.

     The retry loop is what handles collisions among the headings themselves,
     and it replaced a per-base counter whose own output collided with real
     headings: "Foo", "Foo", "Foo 2" gave the second and third heading one id,
     which costs a working index entry (the link map keeps one per key) and
     sends its anchor to the wrong section. It terminates because what it tests
     is finite: neither `used` nor the document grows inside the body, and each
     turn proposes a distinct candidate, so a free one is reached in at most one
     turn more than there are ids already taken. Never put a PATTERN in that
     condition -- tested against a candidate rather than against base, a pattern
     the body can keep re-satisfying never terminates, and guard() catches
     throws, not hangs: a pinned main thread shows no error card, no console
     line, never resumes the diagram chain, and never even lets the run
     deadline's setTimeout fire.

     Two measured properties worth not re-deriving. The loop is quadratic in the
     number of headings sharing one base -- ~30s at ~32k collisions, which no
     brief approaches, but it is a payload-controlled cost. And \w is ASCII-only,
     so a wholly non-Latin heading strips to "" and becomes section, section-2,
     ...; navigation still works, because every link carries data-target and the
     id it names, but the anchors are not readable.

     Object.create(null) is defence in depth rather than the fix: a plain {}
     inherits Object.prototype, and under the old counter a heading titled
     "constructor" found a truthy value in an empty map and two such headings
     shared one id. The retry loop above closes that on its own -- measured, {}
     and no map at all both produce byte-identical output today. It stays
     because it costs nothing and removes a whole class of surprise. */
  var used = Object.create(null);
  function slug(s){
    var base = "h-" + (s.toLowerCase().replace(/[^\w\s-]/g,"").trim().replace(/\s+/g,"-") || "section");
    var id = base, n = 1;
    while (used[id] || document.getElementById(id)) {
      n++; id = base + "-" + n;
    }
    used[id] = true;
    return id;
  }
  var toc = document.getElementById("toc");
  var list = document.createElement("ul");
  var group = null, kids = null;
  /* Task headings attach to the Plan group by REGION, not by heading adjacency.
     Nesting h3s under "whichever h2 came last" is why the plan's tasks have
     been stolen in five consecutive review rounds — by an unnested h3, a stray
     h1, a demoted h2, and a setext h2 manufactured from YAML front matter.
     Each fix removed one trigger and left the mechanism. The sentinel gives an
     exact anchor for where the plan STARTS, so use that instead of adjacency.

     The rule, stated because an earlier version of this comment described one
     the code does not implement: a task-shaped h3 joins the Plan group if it
     FOLLOWS the plan heading anywhere in the document. There is no upper bound
     at the next h2, so a task-shaped h3 under a trailing "## Self-Review" is
     pulled forward into the Plan group, out of document order.

     That membership rule is intentional rather than a gap. render.sh appends
     the sentinel heading and then the whole plan document to EOF, so every h2
     the plan carries of its own legitimately follows the sentinel, and every
     task under those h2s legitimately belongs to the plan. What is odd is the
     index ORDERING alone, and only for a plan that puts task-shaped h3s after a
     later h2 — which this repo's plan template does not.

     The index keeps its own copy of the predicate deliberately. Task 15
     rewrites the DAG's collector into planRegionHeadings() but does not
     consolidate this one: its own assertions pin that, expecting two
     occurrences of the position constant, the second being the line below,
     surviving that refactor untouched. The two copies are semantically
     identical -- same anchor (planH2), same document-position relation, same
     answer for every node -- so this is redundancy, not two rules that could
     disagree. It does mean a change to one is only a change
     to one: anybody altering what "in the plan region" means has to alter both
     deliberately, and the count assertion is what forces them to notice. */
  var planGroup = null, planKids = null;

  /* Three sections, three guards -- not one wrapper around all three. They form
     a one-way chain: the scrollspy and the sidebar both read what this first
     section builds, so a failure upstream degrades what is below it while each
     of those still reports under its own label. One wrapper would make the
     coupling symmetric instead, and the worst case of that is concrete: a
     viewer whose engine lacks the observer API the scrollspy needs would also
     lose the sidebar toggle, and on a narrow viewport that toggle is the only
     way to reach the index at all. A reader who loses the scrollspy and keeps a
     working index has lost a highlight; a reader who loses the toggle has lost
     navigation. */
  guard("index: build", function(){
    /* h2/h3 only. render.sh flattens every surviving H1 to h4, so there is one
       hierarchy. Treating H1 as a peer group let a stray H1 between an H2 and
       its H3s steal those children, emptying the Plan group. */
    Array.prototype.forEach.call(content.querySelectorAll("h2, h3"), function(h){
      /* Same fallback as the DAG builder: Task 11's capture is guarded, so the
         attribute is not guaranteed, and undefined here means "undefined" as an
         index label. */
      var text = h.dataset.toc || h.textContent;
      h.id = slug(text);
      var a = document.createElement("a");
      a.href = "#" + h.id;
      a.textContent = text;
      a.dataset.target = h.id;

      if (h.tagName === "H2") {
        group = document.createElement("li");
        group.className = "toc-group no-kids";
        var row = document.createElement("div"); row.className = "toc-l2";
        var chev = document.createElement("button");
        chev.className = "chevron";
        chev.setAttribute("aria-expanded", "true");
        chev.textContent = "▾";
        a.className = "lvl2";
        row.appendChild(chev); row.appendChild(a);
        kids = document.createElement("ul"); kids.className = "kids";
        group.appendChild(row); group.appendChild(kids);
        list.appendChild(group);
        if (h === planH2) { planGroup = group; planKids = kids; }
        (function(c, k){
          c.addEventListener("click", function(){
            var open = c.getAttribute("aria-expanded") === "true";
            c.setAttribute("aria-expanded", String(!open));
            k.hidden = open;
          });
        })(chev, kids);
      } else if (group) {
        /* `group` is null until the first h2, so an h3 preceding every h2 is
           silently dropped from the index -- it still gets an id and is still
           observed, it just has no entry. The sentinel guarantees at least one
           h2 exists, but not that it precedes the document's first h3, and a
           top-level li with no group has nowhere correct to sit. */
        var owner = group, into = kids;
        if (planKids && /^Task\s+\d+/i.test(text) && planH2 !== h &&
            (planH2.compareDocumentPosition(h) & Node.DOCUMENT_POSITION_FOLLOWING)) {
          owner = planGroup; into = planKids;
        }
        owner.classList.remove("no-kids");
        var li = document.createElement("li");
        li.appendChild(a);
        into.appendChild(li);
      }
    });
    toc.appendChild(list);
  });

  /* ---------- scrollspy ---------- */
  guard("index: scrollspy", function(){
    var links = {};
    Array.prototype.forEach.call(toc.querySelectorAll("a[data-target]"), function(a){ links[a.dataset.target] = a; });
    var visible = {};
    /* Snapshotted once. It stays consistent with the index only while nothing
       later adds, removes or moves a heading -- an invariant a future task could
       break silently, since a heading appearing after this line gets no index
       entry, no id and no observer, with nothing anywhere to say so. Plenty
       mutates the document after this point -- the theme, chevron and sidebar
       handlers all do -- but none of them adds, removes or moves a heading, and
       Task 13's renderer, the one that inserts nodes into #content, touches
       [data-src] boxes only. That is the operative clause, not "nothing runs
       later". */
    var heads = Array.prototype.slice.call(content.querySelectorAll("h2, h3"));
    var obs = new IntersectionObserver(function(entries){
      entries.forEach(function(e){ visible[e.target.id] = e.isIntersecting; });
      /* Re-derived from `heads`, which is in document order, rather than from
         `entries`: the observer makes no ordering guarantee about the records
         it delivers, and trusting them is how most hand-rolled scrollspies pick
         the wrong heading on a fast scroll. */
      var first = heads.filter(function(h){ return visible[h.id]; })[0];
      /* Sticky, and this is the difference between a highlight and no highlight
         for most of the document. rootMargin shrinks the root to the top 30% of
         the viewport, so a heading is "visible" for about 0.3*vh plus its own
         height -- ~310px at vh=900, against sections that run thousands. With
         nothing in that band the clear loop below would strip every active
         class and add none, so the index would sit blank through the body of
         every section. Worse, it is not merely transient: putting heading H in
         the band needs scrollTop >= H.offsetTop - 0.3*vh, and scrollTop tops
         out at docHeight - vh, so ANY heading with less than 0.7 of a viewport
         of content after it can never enter the band at all -- the last section
         of every brief, permanently. Keeping the previous highlight self-
         corrects in both directions, because scrolling back up brings the
         previous heading down through the band from above.

         Resolved to the link FIRST, so the same early return covers the second
         way this goes blank: a heading with no index entry. An h3 preceding
         every h2 gets an id and an observer but no li (see the index walk
         above), so `first` is truthy while links[first.id] is undefined --
         under a `first`-only test the clear loop still ran and nothing was
         added. Measured before the fix: [] -> ['Real Section'] -> []. */
      var a = first && links[first.id];
      if (!a) return;
      Object.keys(links).forEach(function(k){ links[k].classList.remove("active"); });
      a.classList.add("active");
    }, { rootMargin:"0px 0px -70% 0px", threshold:0 });
    heads.forEach(function(h){ obs.observe(h); });
  });

  /* ---------- mobile sidebar ---------- */
  guard("index: mobile sidebar", function(){
    var sb = document.getElementById("sidebar");
    document.getElementById("sbToggle").addEventListener("click", function(){ sb.classList.toggle("open"); });
    toc.addEventListener("click", function(e){ if (e.target.tagName === "A") sb.classList.remove("open"); });
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: the suite reports 249 passed, 0 failed — every appended assertion green, plus Task 13's mirror, whose stop marker this task retargets. Visual confirmation is **walk cases 1 and 3**. Case 1 carries the two checks nothing static here can reach: that an index entry still lands on its own heading after the diagrams have injected their ids, and that the highlight tracks a real scroll without ever going blank.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/template.html assets/change-brief/tests/render_test.sh \
        docs/plans/2026-07-30-visual-change-briefs.md
git commit -m "feat(change-brief): collapsible index with region-scoped task grouping, scrollspy"
```

---

### Task 15: Close the six known open findings — `static-verifiable`

**Depends on:** Task 6, Task 14

These are recorded in the spec's **Known open findings** table. Findings 1 and 2 are one root cause and are fixed together.

**Files:**
- Modify: `assets/change-brief/render.sh`
- Modify: `assets/change-brief/template.html`
- Modify: `assets/change-brief/tests/render_test.sh`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== known findings =="
# F1+F2: front matter with indented values and list entries, longer than 50 lines.
{ printf -- '---\ntags:\n  - a\n  - b\n'; for i in $(seq 1 60); do printf 'k%s: v\n' "$i"; done; printf -- '---\n# Plan FM\n\n### Task 1: A\n'; } > "$W/fm.md"
"$S/render.sh" "$W/s.md" "$W/fm.md" -o "$W/fm.html" >/dev/null
chk "structured front matter dropped" "$(payload "$W/fm.html" | grep -c '^tags:$')" "0"
chk "front matter body retained" "$(payload "$W/fm.html" | grep -c '^### Task 1: A$')" "1"

# F3: a U+2060 in the spec's own heading must not satisfy the sentinel check.
printf '# T\n\n## Fake\342\201\240 Heading\n\nbody\n' > "$W/mark.md"
"$S/render.sh" "$W/mark.md" -o "$W/mark.html" >/dev/null
chk "stray U+2060 stripped from the payload" \
  "$(payload "$W/mark.html" | grep -cF "Fake$(printf '\342\201\240') Heading")" "0"
chk "exactly one sentinel in the payload" \
  "$(payload "$W/mark.html" | grep -oF "$(printf '\342\201\240')" | wc -l | tr -d ' ')" "1"
# The payload check above pins render.sh's half. This pins the page's half:
# taking [0] reinstates "the first marked h2 wins", which IS the finding, and
# reverting to it passed every other assertion in this suite.
chk "the page requires exactly one marked h2, not the first one" \
  "$(grep -cF 'var planH2 = marked_h2s.length === 1 ? marked_h2s[0] : null;' "$S/template.html")" "1"

# F4: diag banners suppressed when the structural check passes.
chk "diag banners gated on the sentinel" \
  "$(grep -c 'if (planH2) return;' "$S/template.html")" "1"

# F5: tasks nested in a list still yield a graph.
# The CALL SITE, pinned exact -- not a bare name count. Task 14's index comment
# names planRegionHeadings in prose, so `grep -c planRegionHeadings` is already
# satisfied by a comment and stays satisfied if the collector is reverted to the
# sibling walk. The declaration itself is pinned, anchored, by "graph scoped by
# plan region" above; this is the line that makes the DAG actually use it.
chk "plan tasks scoped by document position" \
  "$(grep -cF 'tasks = planRegionHeadings().filter(function(h){' "$S/template.html")" "1"

# F6: the pending predicate must be specific.
chk "pending check asserts .callout.pending" \
  "$(grep -c 'querySelector(".callout.pending")' "$S/template.html")" "1"
# Position is load-bearing and no presence grep can see it: .callout.pending
# does not exist until the callout section converts the blockquote, so the same
# predicate placed before that section is false on every pending brief and
# banners "Pending notice missing" on the gate-1 artifact every single time.
callouts_ln=$(grep -n 'guard("decorate: callouts"' "$S/template.html" | head -1 | cut -d: -f1)
pending_ln=$(grep -n 'querySelector(".callout.pending")' "$S/template.html" | head -1 | cut -d: -f1)
if [ -n "$callouts_ln" ] && [ -n "$pending_ln" ] && [ "$callouts_ln" -lt "$pending_ln" ]; then
  ok "the pending check runs after the callout conversion that creates .callout.pending"
else
  no "the pending check runs after the callout conversion that creates .callout.pending" \
     "callouts=[${callouts_ln:-missing}] pending=[${pending_ln:-missing}]"
fi

# The new banner is a top-level section and gets a guard like every other one;
# a bare statement here throws uncaught and kills everything after it.
chk "guarded: guard(\"dag: no tasks banner\"" \
  "$(grep -cF 'guard("dag: no tasks banner"' "$S/template.html")" "1"
# An empty `tasks` has two causes -- no task headings in the source, or a
# caught collect guard -- and only the first is a fact about the document.
# Without this gate the banner makes a confident false claim about the
# reader's source while the headings sit in view below it.
chk "the no-tasks banner is gated on the collect guard having actually run" \
  "$(grep -cF 'planH2 && collected &&' "$S/template.html")" "1"
chk "and that flag is set inside the collect callback, not beside it" \
  "$(grep -c '^    collected = true;$' "$S/template.html")" "1"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: **eleven** FAILs — every assertion in the block above except `front matter body retained`, exit 1.

Measured, not predicted. The earlier draft of this step said seven, which was correct for the earlier draft of Step 1; three assertions were added to it after mutation testing, and one was rewritten. The rewritten one matters: `exactly one sentinel in the payload` was `grep -c "Plan<U+2060>"`, and that counts **1 both before and after the fix** — the fixture's stray marker sits in `Fake<U+2060> Heading`, not in a heading named Plan, so the label's guarantee was never checked on the fixture it runs on. Counting every sentinel character is what the label says and is what discriminates: 2 before the strip, 1 after.

`front matter body retained` is the one assertion that legitimately passes here: the old `has_front_matter` leaves the block in place, so the task heading survives anyway. It is not vacuous — it guards the opposite direction, and it fails if `skip_preamble` is made to consume past the closing `---` (verified by mutation).

- [ ] **Step 3a: Fix findings 1 and 2 — front-matter detection**

In `assets/change-brief/render.sh`, replace the `has_front_matter` function with:

```bash
has_front_matter() {
  head -n 1 "$1" | grep -q '^---[[:space:]]*$' || return 1
  # Requiring a closing "---" IS the guard; a line cap is a failure threshold,
  # not a safety property. Accept indented continuations and list entries so a
  # block like "tags:\n  - a" is still recognised as front matter.
  awk 'NR == 2 && !/^[A-Za-z_][A-Za-z0-9_.-]*:/ { exit }
       NR > 1 && /^---[ \t]*$/ { found = 1; exit }
       NR > 1 && /^[ \t]/ { next }
       NR > 1 && /^- / { next }
       NR > 1 && /^[ \t]*$/ { next }
       NR > 1 && !/^[A-Za-z_][A-Za-z0-9_.-]*:/ { exit }
       END { exit !found }' "$1"
}
```

- [ ] **Step 3b: Fix finding 3 — sentinel uniqueness**

In `assets/change-brief/render.sh`, strip any pre-existing U+2060 before appending the sentinel. Replace the `strip_h1 "$SPEC" > "$TMP/payload.md"` line with:

```bash
# Strip any U+2060 already present in the sources so the sentinel is unique by
# construction. A spec containing one in its own h2 would otherwise satisfy the
# integrity assertion, letting loss after that point go unreported.
strip_h1 "$SPEC" | LC_ALL=C sed 's/\xe2\x81\xa0//g' > "$TMP/payload.md"
```

and the plan branch's `strip_h1 "$PLAN" >> "$TMP/payload.md"` with:

```bash
  strip_h1 "$PLAN" | LC_ALL=C sed 's/\xe2\x81\xa0//g' >> "$TMP/payload.md"
```

In `assets/change-brief/template.html`, assert exactly one sentinel. Replace **both** the `var PLAN_MARK = "\u2060";` line **and** the `var planH2 = ...` assignment that follows it (the block below re-declares `PLAN_MARK`; leaving the original in place yields a duplicate `var` declaration, which is legal JS but flips Task 10's `PLAN_MARK` count assertion to 2):

```js
  var PLAN_MARK = "\u2060";
  var marked_h2s = Array.prototype.filter.call(content.querySelectorAll("h2"), function(h){
    return h.textContent.indexOf(PLAN_MARK) !== -1;
  });
  var planH2 = marked_h2s.length === 1 ? marked_h2s[0] : null;
```

- [ ] **Step 3c: Fix finding 4 — suppress diag banners when the page is intact**

In `assets/change-brief/template.html`, replace the diagnostics loop with:

```js
  /* Warnings render.sh detected before parsing. Suppressed when the structural
     check passed: the scanner is approximate by design and fabricates
     "unterminated fence" on a backtick info string containing a backtick. A
     reader-facing banner that cries wolf on a correct brief disarms the
     backstop. The stderr line still reaches the author. */
  decodeB64(document.body.dataset.diag).split("\n").forEach(function(w){
    if (planH2) return;
    if (w.trim()) banner("Source problem", w.trim());
  });
```

- [ ] **Step 3d: Fix finding 5 — scope tasks by document position**

Three edits in `assets/change-brief/template.html`, in source order. They are given
separately on purpose: the code they replace is **not contiguous** — Task 12's
`var tasks = [];` declaration sits between the helper and the guard, and it must stay
there. Applying this as one block deletes that declaration, and `tasks` and `collected`
then both die with a `ReferenceError` in every section that reads them (reproduced).

**(i)** Replace the `planTasks` function together with the comment block directly above it —
the one beginning "Scoped to the plan region" — with:

```js
  /* compareDocumentPosition, not the sibling chain: tasks nested inside a list,
     a blockquote, or a <details> are not siblings of the sentinel and yielded
     no graph at all, silently.

     Note what this costs. planTasks() guaranteed every heading it returned was
     a direct child of #content, and that invariant is gone: an h3 the markdown
     renderer nested inside an <li> now qualifies. Task 12 anchors the diagram
     and its caption on planH2 precisely because of this — anchoring on the
     first task's parent would bury both inside that list item. That anchoring
     must stay.

     A helper, not a section: like sectionNodes above it stays unwrapped at
     IIFE scope on purpose, since a guard() would scope the declaration to that
     callback and its caller would die under the wrong label. */
  function planRegionHeadings(){
    if (!planH2) return [];
    return Array.prototype.filter.call(content.querySelectorAll("h3"), function(h){
      return !!(planH2.compareDocumentPosition(h) & Node.DOCUMENT_POSITION_FOLLOWING);
    });
  }
```

**(ii)** Leave `var tasks = [];` and the comment above it exactly where they are. Add one
line immediately after `var tasks = [];`, at the same IIFE scope and for the same reason —
a `var` inside a guard callback is invisible to the sibling statements that read it:

```js
  var collected = false;
```

**(iii)** Replace the body of the existing `guard("dag: collect plan tasks", …)` callback,
and append a second guarded section directly after it, before
`guard("dag: build and insert graph", …)`:

```js
  guard("dag: collect plan tasks", function(){
    tasks = planRegionHeadings().filter(function(h){
      return /^Task\s+\d+/i.test(h.dataset.toc || h.textContent);
    });
    collected = true;
  });
  /* Gated on `collected`, not on tasks.length alone. An empty `tasks` has two
     causes — the document genuinely has no task headings, or the guard above
     caught — and only the first is a fact about the source. Firing on the
     second prints a confident false claim about the reader's document with the
     task headings visible directly below the banner, which is exactly what the
     comment on that filter forbids. Guarded per the Tasks 9-14 containment
     doctrine: a bare top-level statement here throws uncaught and kills every
     section after it. */
  guard("dag: no tasks banner", function(){
    if (planH2 && collected && document.body.dataset.planState === "attached" && !tasks.length) {
      banner("No tasks found",
        "This brief was rendered with a plan attached, but no task headings were " +
        "found in the Plan section. The dependency graph is missing.");
    }
  });
```

The comment that already sits above the collect guard — the one explaining the
`(h.dataset.toc || h.textContent)` fallback — stays as it is; it still describes the filter
inside the new body, and it is the reason the banner must not fire on a caught guard.

- [ ] **Step 3e: Fix finding 6 — specific pending predicate**

In `assets/change-brief/template.html`, replace the pending-notice check with:

```js
  if (planH2 && document.body.dataset.planState === "pending" &&
      !content.querySelector(".callout.pending")) {
    banner("Pending notice missing",
      "This brief was rendered before the plan was written, but the notice " +
      "saying so did not render. Treat the Plan section as unwritten.");
  }
```

Move this check to **after** the callout conversion section, since `.callout.pending` does not exist until blockquotes are converted.

- [ ] **Step 3f: Retarget the assertions this rename invalidates**

The suite is cumulative and re-run in full, so Step 3d's rename breaks earlier
assertions. Update them in place rather than letting them fail.

In `assets/change-brief/tests/render_test.sh`, under `== template JS: dependency graph ==`,
replace:

```bash
chk "graph scoped by plan region" \
  "$(grep -c '^  function planTasks' "$S/template.html")" "1"
```

with:

```bash
chk "graph scoped by plan region" \
  "$(grep -c '^  function planRegionHeadings' "$S/template.html")" "1"
```

Keep the `^  ` anchor through the rename. It is the whole assertion: an unanchored
`grep -c 'function planRegionHeadings'` still counts 1 when the declaration is wrapped in a
`guard()` — the exact regression the label exists to forbid, and the one the `sectionNodes`
assertion above was already fixed for once.

Three assertions in that same block are expected to **survive Step 3d untouched** —
`^  var tasks = \[\];`, `^    tasks = plan`, and the `planH2`-before-collect source-order
check. They pass only because Step 3d keeps the hoisted declaration and assigns into it. If
any of the three fails, Step 3d was applied wrongly; retargeting them is the wrong fix.

Step 3d adds a twentieth guarded section, so raise the containment floor. Task 14 left three floors in the suite (`-ge 15`, `-ge 16` and `-ge 19`); `-ge 19` is the live one, and it is the block to retarget. Replace:

```bash
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 19 ] && ok "at least 19 top-level sections guarded (floor raised by this task)" \
  || no "at least 19 top-level sections guarded (floor raised by this task)" "$n"
```

with:

```bash
n=$(grep -c 'guard("' "$S/template.html")
[ "$n" -ge 20 ] && ok "at least 20 top-level sections guarded (floor raised by this task)" \
  || no "at least 20 top-level sections guarded (floor raised by this task)" "$n"
```

and under `== template JS: index ==`, replace:

```bash
chk "tasks attach by document position" \
  "$(grep -c 'DOCUMENT_POSITION_FOLLOWING' "$S/template.html")" "1"
```

with:

```bash
chk "tasks attach by document position" \
  "$(grep -c 'DOCUMENT_POSITION_FOLLOWING' "$S/template.html")" "2"
```

- [ ] **Step 3g: Regenerate Task 12's mirrored snippet, and record the `mq` decision**

Step 3d edits code that sits **inside Task 12's mirrored slice** (`DAG_HEAD` to the
walk-tag badges header), so `mirror_chk "Task 12's plan snippet is byte-identical to
the shipped template"` fails until that fence is regenerated. Regenerate it *from*
`assets/change-brief/template.html` — do not hand-edit it — exactly as Task 14 did for
Task 13's stop marker. This is the mechanism working as designed: an un-regenerated
snippet is a stale instruction, which is what `mirror_chk` exists to catch.

Separately, `var mq = window.matchMedia(...)` is a top-level statement outside any
`guard()`. It has now been assessed twice and is deliberately left alone; record the
reasoning at the site so a third review does not re-open it:

```js
  /* Deliberately NOT wrapped in guard(), assessed twice and recorded here so it
     is not re-litigated a third time. This file already hard-requires
     TextDecoder, dataset, atob and replaceWith, every one of them newer than
     matchMedia, so the set of engines carrying those and not this one is empty
     -- a guard here would be unreachable code paying a real cost in noise. The
     genuine compatibility risk in this area is mq.addEventListener, which
     Safari did not ship until 14, and that call IS guarded below. */
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: all twelve known-finding assertions PASS and no earlier assertion regresses.
The suite reports **261 passed, 0 failed**. Exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/render.sh assets/change-brief/template.html assets/change-brief/tests/render_test.sh docs/plans/2026-07-30-visual-change-briefs.md
git commit -m "fix(change-brief): close the six known findings from spec review"
```

---

### Task 16: Consolidate the shell test suite — `static-verifiable`

**Depends on:** Task 15

**Files:**
- Modify: `assets/change-brief/tests/render_test.sh`
- Create: `assets/change-brief/tests/fixtures/spec.md`
- Create: `assets/change-brief/tests/fixtures/plan.md`
- Create: `assets/change-brief/tests/fixtures/hostile-title.md`
- Create: `assets/change-brief/tests/fixtures/broken-diagram.md`
- Create: `assets/change-brief/tests/fixtures/beacon.md`
- Create: `assets/change-brief/tests/fixtures/comment-truncation.md`
- Create: `assets/change-brief/tests/fixtures/plan-region.md`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`. The block pins the fixtures' *contents*, not just their presence: a fixture is an assertion's input, so its bytes are the guarantee — one that silently loses a load-bearing line turns the assertion reading it into a tautology that still reports PASS.

```bash
echo "== fixtures =="
for f in spec plan hostile-title broken-diagram beacon comment-truncation plan-region; do
  P="$S/tests/fixtures/$f.md"
  { [ -f "$P" ] && [ -s "$P" ]; } && ok "fixture $f.md present and non-empty" \
    || no "fixture $f.md present and non-empty" "missing, empty, or not a regular file"
done
# A fixture is an assertion's input. An input that quietly loses its
# load-bearing line turns the assertion reading it into a tautology, and
# that assertion still reports PASS. Measured: with the fence below removed,
# Task 17's deadAnchors probe reports [] against a template with the h-
# prefix deleted -- i.e. it passes whether the template is right or wrong.
PR="$S/tests/fixtures/plan-region.md"
chk "plan-region.md carries the sequence fence deadAnchors needs" \
  "$(grep -c '^sequenceDiagram$' "$PR")" "1"
chk "plan-region.md carries the ## Database heading that collides with it" \
  "$(grep -c '^## Database$' "$PR")" "1"
# getElementById returns the first match in document order, so the fence must
# precede the heading or the collision cannot happen at all.
fence_ln=$(grep -n '^sequenceDiagram$' "$PR" | cut -d: -f1)
db_ln=$(grep -n '^## Database$' "$PR" | cut -d: -f1)
if [ -n "$fence_ln" ] && [ -n "$db_ln" ] && [ "$fence_ln" -lt "$db_ln" ]; then
  ok "the sequence fence precedes ## Database, which the collision depends on"
else
  no "the sequence fence precedes ## Database, which the collision depends on" \
     "fence=[${fence_ln:-missing}] db=[${db_ln:-missing}]"
fi
chk "plan-region.md carries its own ## Plan and a task-shaped h3" \
  "$(grep -c '^## Plan$' "$PR")$(grep -c '^### Task 1: Example' "$PR")" "11"
B="$S/tests/fixtures/beacon.md"
# `^%%{init:` counted line starts, not bypass attempts. Measured: replacing both
# directives with `%%{init: {}}%%` left the whole suite green while Task 17's
# foreignObjects and styleBeacons probes went tautological -- an inert directive
# asks for nothing, so both report 0 against a template with the `secure` list
# deleted. Pin what each probe actually does, and pin the count alongside the
# htmlLabels one so a third directive cannot appear unnoticed. Which fence
# comes first is deliberately NOT pinned: each directive governs its own
# fence, so swapping them changes no probe, and a check may not claim an
# ordering it does not test.
chk "beacon.md carries exactly two init directives, one re-enabling htmlLabels" \
  "$(grep -c '^%%{init:' "$B")$(grep -cxF '%%{init: {"flowchart": {"htmlLabels": true}}}%%' "$B")" "21"
# A separate check rather than a third term concatenated above: one combined
# total would still pass with either probe neutered as long as the other
# survived, and independence is the whole point -- these are two different
# bypasses, and the themeCSS one outlived the round that closed the other.
chk "beacon.md's themeCSS directive is aimed at the payload host" \
  "$(grep -cxF '%%{init: {"themeCSS": "@font-face{font-family:pwn;src:url(https://evil.example.invalid/p.woff2);} text{font-family:pwn;}"}}%%' "$B")" "1"
# Task 17's styleBeacons filter greps live <style> for this exact literal, so
# renaming the host makes that probe report 0 whether the template is right or
# wrong. Three lines carry it -- the UNC link, the flowchart node label's <img>
# target, and the @font-face url() above -- and only the third is inside a
# directive, so the line above cannot stand in for this one.
chk "beacon.md keeps the payload host on all three lines that carry it" \
  "$(grep -c 'evil\.example\.invalid' "$B")" "3"
chk "beacon.md carries the executable-URL probes" \
  "$(grep -c 'javascript:window.__PWN=1' "$B")$(grep -c 'onerror=' "$B")" "11"
chk "broken-diagram.md carries three mermaid fences" \
  "$(grep -c '^```mermaid$' "$S/tests/fixtures/broken-diagram.md")" "3"
chk "plan.md declares the forward reference" \
  "$(grep -c '^\*\*Depends on:\*\* Task 1, Task 99$' "$S/tests/fixtures/plan.md")" "1"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected, measured with `fixtures/` absent: 17 FAILs — `shell: 261 passed, 17 failed` — exit 1.

- [ ] **Step 3: Create the fixtures**

`assets/change-brief/tests/fixtures/spec.md`:

````markdown
# Fixture Spec

## Why this change

A fixture used by render_test.sh and verify.mjs.

## Design

```mermaid
flowchart LR
  A[Start] --> B[End]
```
````

`assets/change-brief/tests/fixtures/plan.md`:

```markdown
# Fixture Implementation Plan

### Task 1: Alpha — `static-verifiable`

**Depends on:** none

- [x] **Step 1: done**
- [ ] **Step 2: pending**

### Task 2: Beta — `browser-walk-only`

**Depends on:** Task 1

- [ ] **Step 1: pending**

### Task 3: Gamma — `static-verifiable`

**Depends on:** Task 1, Task 99

Prose mentioning `Depends on: Task 2` must not create an edge.

- [ ] **Step 1: pending**

## Browser-Walk Inventory

1. Open the brief and confirm the graph shows only declared edges.
```

`assets/change-brief/tests/fixtures/hostile-title.md`:

```markdown
# Auth | Session & <redesign> "x" \ y

## Why this change

Title metacharacters must survive without becoming markup.
```

`assets/change-brief/tests/fixtures/broken-diagram.md`:

````markdown
# Broken Diagram

## Design

```mermaid
flowchart LR
  A --> B
```

```mermaid
this is not valid mermaid at all {{{
```

```mermaid
flowchart TB
  C --> D
```
````

`assets/change-brief/tests/fixtures/beacon.md`:

````markdown
# Beacon Fixture

## Why this change

Remote image: ![tracker](https://example.invalid/px.gif)

Raw HTML: <img src=x onerror="window.__PWN=1">

Bad link: [click](javascript:window.__PWN=1)

UNC link: [unc](/\evil.example.invalid/share)

Good link: [BLOCKS](BLOCKS.md) and [fragment](#design) and [web](https://example.com/).

Directive-bypass probes. The first tries to put `htmlLabels` back and beacon through a
node label; without Task 13's `secure` list it produces a live `<img>` and hangs the
renderer. The second needs neither, and is the one that survived the round which closed
the first: `themeCSS` is concatenated verbatim into the emitted `<style>`, so an
`@font-face` plus a rule that uses it fetches a font from a host of the payload's
choosing.

```mermaid
%%{init: {"flowchart": {"htmlLabels": true}}}%%
flowchart LR
  A["<img src=https://evil.example.invalid/x.png>"] --> B["<b>bold</b>"]
```

```mermaid
%%{init: {"themeCSS": "@font-face{font-family:pwn;src:url(https://evil.example.invalid/p.woff2);} text{font-family:pwn;}"}}%%
flowchart LR
  C[themeCSS probe] --> D[still renders]
```
````

`assets/change-brief/tests/fixtures/comment-truncation.md`:

```markdown
# Comment Truncation

## Why this change

An arrow --> appears in prose before the dangling opener below.

<!-- this comment is never closed

## Later Section

This section must still render.
```

`assets/change-brief/tests/fixtures/plan-region.md` — a spec that deliberately collides with every heuristic the plan region has to survive: it carries its own `## Plan` section, its own `### Task 1:` heading, and (paired with `plan.md`) a foreign `##` between the sentinel and the real tasks. One fixture closes three `static-verifiable` requirements that were otherwise covered only by the browser walk. It also carries a `sequenceDiagram` fence followed by a `## Database` heading, and that pairing is load-bearing rather than decoration: `database` is one of eight ids the diagram library emits unnamespaced that a lowercased heading can reach, and the fence has to come first, because `getElementById` returns the first match in document order. That is what gives the `deadAnchors` assertion below something it can actually fail on. Measured through the real pipeline: amended fixture, prefix present -> `[]`; amended fixture, `h-` prefix deleted from `slug` -> `["database"]`; **unamended fixture, prefix deleted -> `[]`**. Without the fence and the heading the assertion passes whether the template is correct or not. If you change this fixture, re-run that third case before trusting the check.

````markdown
# Plan Region Collision Fixture

## Why this change

A spec that talks about plans, using the plan vocabulary in its own prose.

```mermaid
sequenceDiagram
  autonumber
  Reviewer->>Brief: opens
  Brief-->>Reviewer: renders
```

## Plan

This is the spec's own rollout plan, not the task list. It must not capture the
task dependency graph, and it must not become the sentinel heading.

### Task 1: Example quoted from the block catalog

Prose illustrating the task format. This heading is task-shaped but lives in the
spec, so it must not appear in the Plan index group and must not emit a graph node.

## Design

Body.

## Database

A section name that slugs onto an id the diagram library emits unnamespaced. The
sequence fence above precedes it, so with the heading-id prefix removed this
heading's index entry resolves to a <symbol> in <defs> instead of to the heading.
````

- [ ] **Step 4: Run the suite to verify it passes**

Expected: all seventeen fixture assertions PASS. Confirm the whole suite is green and exits 0:

```bash
bash assets/change-brief/tests/render_test.sh; echo "exit=$?"
```
Expected, measured: `shell: 278 passed, 0 failed`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/tests/
git commit -m "test(change-brief): fixtures and consolidated shell assertions"
```

---

### Task 17: Optional headless browser harness — `static-verifiable`

**Depends on:** Task 15

Optional tooling, not a dependency of the change. Where it cannot run, its assertions fall to the numbered walk cases.

**Files:**
- Create: `assets/change-brief/tests/browser/package.json`
- Create: `assets/change-brief/tests/browser/verify.mjs`
- Create: `assets/change-brief/tests/browser/.gitignore`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`. Presence checks are not enough, for the same reason Task 16 replaced them for the fixtures — but the failure mode differs in kind here, and the difference is what the block is shaped around. A fixture that loses a load-bearing line goes undetected because nothing reads it closely; `verify.mjs` is executable, so a gutted copy is caught by *running* it. The gap is that the shell suite cannot run it: a bare checkout has no `npm` and no browser, which is precisely why the harness is optional.

So the block pins what reading the file can settle — and pins each observation at every link in its chain. A probe reads as `query -> filter -> record`, and all three can be neutered silently while the other two stay honest: `querySelectorAll('style')` typed wrong searches nothing, and searching nothing for the right host literal reports 0 exactly like searching everything for the wrong one. An earlier revision of this block pinned only the filters, and eight of thirteen planted mutations survived both it and a green harness run.

```bash
echo "== browser harness =="
# The shell suite cannot RUN this harness: a bare checkout has no npm and no
# browser, which is the whole reason the harness is optional. So presence is all
# the suite can observe -- and presence is not enough. A verify.mjs that has
# quietly lost half its assertions is byte-different and status-identical.
# Two things reading the file can settle. First the assertion inventory: the
# count moves only when an assertion is deliberately added or removed, and that
# edit has to come here too. Second, the probes whose PASSING value is the empty
# one. A probe expecting 0 or [] reports a pass when its selector matches
# nothing, so a typo in one is invisible to the shell AND to a green harness run
# -- measured: gutting the template's mermaid `secure` list fails three of those
# assertions and removing the template's h- heading prefix fails deadAnchors,
# but only while the selectors below still name what they claim to.
# Deliberately NOT pinned, because breaking them fails loudly rather than
# silently and pinning them would churn on ordinary edits: the chk messages, the
# launcher, the timeouts, and every probe whose expected value is non-zero -- a
# wrong selector there reports 0 against an expectation of 1 and fails on sight.
for f in package.json verify.mjs .gitignore; do
  P="$S/tests/browser/$f"
  { [ -f "$P" ] && [ -s "$P" ]; } && ok "browser harness $f present and non-empty" \
    || no "browser harness $f present and non-empty" "missing, empty, or not a regular file"
done
BP="$S/tests/browser/package.json"
# Neither half is optional: without the dependency `npm install` installs
# nothing and the import cannot resolve; without the type field node refuses
# verify.mjs's top-level import outright.
chk "package.json declares playwright-core and marks the directory ESM" \
  "$(grep -cF '"playwright-core"' "$BP")$(grep -cF '"type": "module"' "$BP")" "11"
GI="$S/tests/browser/.gitignore"
# `npm install` here drops thousands of files inside a tracked tree. Matched
# whole-line: git does not strip a trailing \r from an ignore pattern, so a CRLF
# checkout of this file ignores nothing at all, and -x is what sees that.
chk ".gitignore covers both artefacts npm install leaves here" \
  "$(grep -cxF 'node_modules/' "$GI")$(grep -cxF 'package-lock.json' "$GI")" "11"
V="$S/tests/browser/verify.mjs"
# Three terms, because pinning any two leaves the third free: the source count,
# the constant it is compared against, and the comparison itself. Measured --
# with only the first two pinned, deleting the `pass + fail !== EXPECTED` block
# reported 38 passed, 0 failed and a green suite; and with only the first
# pinned, disabling an assertion block AND lowering the constant to match
# reported 27 passed, 0 failed, exit 0, with nothing anywhere going red.
#
# 40 call sites against a 38-assertion suite is not a discrepancy: the canary
# pinned below calls chk twice on purpose and restores the counters, so the two
# numbers are meant to differ by exactly two. Adding or removing a real
# assertion moves both, and this line is where they are held together.
chk "verify.mjs still carries its whole assertion inventory, and rechecks it at runtime" \
  "$(grep -c '^ *chk(' "$V")/$(grep -cF 'const EXPECTED = 38;' "$V")$(grep -cF 'pass + fail !== EXPECTED' "$V")" "40/11"
# Task 13's two bypasses, kept as two checks for the same reason the fixture
# pins above keep them apart: they are independent, and the themeCSS one
# outlived the round that closed the htmlLabels one.
# Every assertion in verify.mjs is worth exactly what chk is worth, and chk
# rewritten to `(m, got, want) => ok(m)` keeps the source count and every pinned
# selector below intact. Measured: so neutered, the harness certified a page
# firing four live requests to evil.example.invalid as 38 passed, 0 failed,
# while this suite stayed green -- the worst failure mode the harness has, and
# invisible to every other pin here. Both terms are pinned for the reason the
# EXPECTED comment above gives: a canary that computes a verdict it never raises
# is exactly as blind as no canary, so the throw is pinned, not just the call.
chk "verify.mjs self-tests chk before trusting it, and raises the verdict by throwing" \
  "$(grep -cF "chk('canary: a mismatched pair must fail', 1, 2);" "$V")$(grep -cF "throw new Error('harness self-test failed" "$V")" "11"
chk "verify.mjs's htmlLabels probe still counts foreignObject" \
  "$(grep -cF "querySelectorAll('foreignObject')" "$V")" "1"
# The paired half of the beacon.md pin above: this probe greps live <style> for
# the host as a literal, so a rename on either side makes it report 0 whether
# the template is right or wrong. The QUERY is pinned alongside the filter --
# `querySelectorAll('style')` typed wrong searches nothing, and searching
# nothing for the right literal reports 0 exactly like searching everything for
# the wrong one. Every pin below carries the same pairing, for the same reason.
chk "verify.mjs's themeCSS probe still names both the element set and the host" \
  "$(grep -cF "querySelectorAll('style')" "$V")$(grep -cF "includes('evil.example.invalid')" "$V")" "11"
# deadAnchors is [] both when every index entry resolves to its own heading and
# when the test of what it resolved TO is deleted. That tagName match is the
# entire discriminator for the collision property Task 15 exists for.
chk "verify.mjs's deadAnchors probe still names its entries and tests what they resolved to" \
  "$(grep -cF "'#toc a[data-target]'" "$V")$(grep -cF '/^H[23]$/' "$V")" "11"
# The rest of the empty-expectation set. Concatenated, not summed: a sum still
# totals right with one term at zero and another at two, a concatenation cannot.
# `p.on('request'` is the only network observation in the entire feature: with
# that event name typed wrong nothing is ever collected, and BOTH offsite
# assertions report [] while the page beacons freely. Measured against a
# template with the mermaid `secure` list gutted: four live requests to
# evil.example.invalid, both probes green.
chk "verify.mjs's inertness probes still name their selectors" \
  "$(grep -cF '[id^="dmmd-"], [id^="immd-"]' "$V")$(grep -cF "p.on('request'" "$V")$(grep -cF "startsWith('file://')" "$V")$(grep -cF 'reqs.push(r.url())' "$V")$(grep -cF 'window.__PWN === undefined' "$V")" "11111"
# The listener BODY is pinned, not just its registration: with errs.push gone
# the handler runs and records nothing, and all five "no page errors"
# assertions go vacuous at once. Measured against a template carrying an
# injected `setTimeout(() => __definitely_not_defined__(), 0)`: the clean file
# reports 5 failures, the neutered one reports none.
chk "verify.mjs's integrity probes still name their selectors" \
  "$(grep -cF "querySelectorAll('.integrity-banner')" "$V")$(grep -cF "querySelectorAll('#content h1')" "$V")$(grep -cF "p.on('pageerror'" "$V")$(grep -cF 'errs.push(e.message)' "$V")" "1111"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected, measured with `tests/browser/` absent: 12 FAILs — `shell: 278 passed, 12 failed` — exit 1.

- [ ] **Step 3: Create the harness**

`assets/change-brief/tests/browser/package.json`:

```json
{
  "name": "change-brief-browser-tests",
  "private": true,
  "type": "module",
  "description": "Optional headless smoke test for rendered change briefs. Without this manifest verify.mjs cannot resolve its import, and without \"type\": \"module\" node refuses to run its top-level import at all.",
  "dependencies": {
    "playwright-core": "^1.62.0"
  }
}
```

`assets/change-brief/tests/browser/.gitignore`:

```gitignore
node_modules/
package-lock.json
```

`assets/change-brief/tests/browser/verify.mjs`:

```javascript
// Optional headless smoke test for rendered change briefs. Where it cannot run,
// these assertions fall to the numbered walk cases in the plan's Browser-Walk
// Inventory -- nothing in the shell suite or the render pipeline depends on it.
//
//   cd assets/change-brief/tests/browser && npm install && node verify.mjs
//
// Exit codes are three-valued on purpose: 0 every assertion passed, 1 an
// assertion failed, 2 no browser to run against. A skip that exited 0 would
// read as a pass in any wrapper that only looks at the status.
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ASSETS = resolve(HERE, '../..');
const FIX = join(ASSETS, 'tests/fixtures');
const W = mkdtempSync(join(tmpdir(), 'brief-'));
// render_test.sh does `trap 'rm -rf "$W"' EXIT`; match it. Registered at the
// point of creation so it fires on every exit -- the no-browser skip below, an
// assertion failure, and a throw out of render() alike. Measured before this
// line existed: 55 leaked brief-* directories holding 1.1 GB.
process.on('exit', () => rmSync(W, { recursive: true, force: true }));

// render_test.sh pins the number of chk() calls this file CONTAINS. This pins
// the number it actually RUNS, which is a different guarantee: an assertion
// block wrapped in `if (false)`, commented out, or rewritten to compare a value
// to itself leaves the source count intact while the run silently covers less.
// Measured: `// 4. Inertness.\n{` -> `if (false) {` reported 26 passed, 0
// failed, exit 0. Keep this in step with render_test.sh's inventory pin; both
// move together, and so does the plan's Step 4 number.
const EXPECTED = 38;

let pass = 0, fail = 0;
const ok = m => { console.log('  PASS  ' + m); pass++; };
const no = (m, d) => { console.log('  FAIL  ' + m + ' :: ' + d); fail++; };
const chk = (m, got, want) =>
  JSON.stringify(got) === JSON.stringify(want) ? ok(m) : no(m, `expected ${JSON.stringify(want)} got ${JSON.stringify(got)}`);

// The harness's own smoke test, run before anything else, because every
// assertion in this file is worth exactly what chk is worth. Rewriting the
// comparison away -- `const chk = (m, got, want) => ok(m);` -- is one line, it
// leaves the source count and every pinned selector intact, and it is the worst
// failure this harness has: measured, a chk neutered that way certified a page
// firing four live requests to evil.example.invalid as `38 passed, 0 failed`,
// with the shell suite green alongside it.
//
// It reports by THROWING, not through no(). Reporting through no() would work
// while only chk is neutered, but it would go silent the moment no() is itself
// the broken thing -- and "the reporting path can be trusted" is the whole
// proposition being established here, so the check may not lean on any part of
// it. A throw needs neither helper: the process dies non-zero, with a message,
// before a single real assertion has run. Both directions are exercised, so a
// chk stubbed to always FAIL is caught by the same block.
//
// The counters are restored afterwards, so the canary costs nothing against
// EXPECTED: the suite is 38 assertions while the file holds 40 chk( call sites.
// render_test.sh pins both numbers, and they are meant to differ by exactly the
// two calls below.
{
  const p0 = pass, f0 = fail, say = console.log;
  let detected, reported;
  // A FAIL line printed by a healthy run teaches readers to skim past FAIL
  // lines, so the canary's own output is swallowed. finally, because a chk that
  // throws rather than returning must not leave the console muted.
  console.log = () => {};
  try {
    chk('canary: a mismatched pair must fail', 1, 2);
    detected = fail === f0 + 1 && pass === p0;
    chk('canary: a matching pair must pass', 1, 1);
    reported = pass === p0 + 1;
  } finally {
    console.log = say;
    pass = p0; fail = f0;
  }
  if (!detected || !reported) {
    throw new Error('harness self-test failed: a mismatched pair ' +
      (detected ? 'failed' : 'did NOT fail') + ' and a matching pair ' +
      (reported ? 'passed' : 'did NOT pass') +
      '. chk/ok/no are not reporting, so every assertion in this file is void.');
  }
}

function render(spec, plan, out) {
  const args = plan ? [spec, plan, '-o', out] : [spec, '-o', out];
  try {
    execFileSync(join(ASSETS, 'render.sh'), args, { stdio: 'pipe' });
  } catch (e) {
    // stdio:'pipe' swallows render.sh's diagnostics, and its message names the
    // real cause every time it refuses (CRLF input, unreadable plan, template
    // placeholder gone). Surfacing it turns "Command failed" into the answer.
    throw new Error(`render.sh failed for ${spec}:\n${e.stderr ? e.stderr.toString().trim() : e.message}`);
  }
  return out;
}

// Two launchers, most reproducible first. The managed build is the one
// `npx playwright install chromium` fetches, pinned to the playwright-core in
// package.json, so a run here means the same as a run anywhere. A system Google
// Chrome is the fallback that needs no download. The fallback is not
// hypothetical: on the machine this was written on the managed build is absent
// -- the cache holds chromium revision 1228 and playwright-core 1.62.1 asks for
// 1234 -- and the system Chrome answers.
const LAUNCHERS = [
  ['playwright chromium', {}],
  ['system chrome', { channel: 'chrome' }]
];

async function launch() {
  const why = [];
  for (const [label, opts] of LAUNCHERS) {
    try {
      return await chromium.launch(opts);
    } catch (e) {
      why.push(`  ${label}: ${String(e.message).split('\n')[0].trim()}`);
    }
  }
  // A stack trace here would name playwright's internals, not the one thing the
  // reader has to do about it.
  console.log('browser: skipped -- no usable browser on this machine.');
  console.log(why.join('\n'));
  console.log('\nInstall one of them, then re-run:');
  console.log('  npx playwright install chromium     # playwright\'s own pinned build');
  console.log('  ...or install Google Chrome         # used as-is, no download');
  console.log('\nWalk cases 1-11 in the plan cover the same ground by hand.');
  process.exit(2);
}

const browser = await launch();

async function probe(file) {
  const ctx = await browser.newContext();
  const p = await ctx.newPage();
  const errs = [], reqs = [];
  p.on('pageerror', e => errs.push(e.message));
  p.on('request', r => { if (!r.url().startsWith('file://')) reqs.push(r.url()); });
  await p.goto('file://' + file);
  // The page marks its own completion (Task 13). Waiting on that instead of a
  // fixed sleep is what distinguishes "still rendering" from "stalled", and it
  // is set on every path that ends the run -- including the ones that fail.
  await p.waitForSelector('[data-diagrams]', { timeout: 30000 });
  const r = await p.evaluate(() => ({
    banners: [...document.querySelectorAll('.integrity-banner')].map(b => b.textContent.slice(0, 40)),
    light: document.querySelectorAll('.mermaid-block .d-light svg').length,
    dark: document.querySelectorAll('.mermaid-block .d-dark svg').length,
    errBoxes: document.querySelectorAll('.mermaid-error').length,
    // Task 13's Critical: a payload init directive re-enabling htmlLabels builds
    // labels as HTML, which is how a live <img> reaches the document. Zero
    // <foreignObject> is the observable proof the secure list still holds.
    foreignObjects: document.querySelectorAll('foreignObject').length,
    // Mermaid leaves its temp container attached to <body> on every failure
    // exit; it carries mermaid's own error graphic, outside .shell, unclassed.
    orphans: document.querySelectorAll('[id^="dmmd-"], [id^="immd-"]').length,
    // themeCSS is concatenated verbatim into the emitted <style>. Counting live
    // <style> elements that carry a payload host is the only thing that sees it:
    // it needs no <foreignObject>, no <img>, and leaves the diagram rendering
    // normally, so every other probe here reads clean while it is wide open.
    styleBeacons: [...document.querySelectorAll('style')]
      .filter(n => n.isConnected && n.textContent.includes('evil.example.invalid')).length,
    diagramsState: document.documentElement.getAttribute('data-diagrams'),
    contentH1: document.querySelectorAll('#content h1').length,
    pending: document.querySelectorAll('.callout.pending').length,
    groups: [...document.querySelectorAll('.toc-group')].map(g => ({
      h2: g.querySelector('a.lvl2').textContent,
      kids: [...g.querySelectorAll('.kids a')].map(a => a.textContent)
    })),
    anchors: [...document.querySelectorAll('#content a')].map(a => ({ href: a.getAttribute('href'), host: a.host })),
    // Every index entry must resolve to its own heading. This runs after the
    // waitForSelector above, so the diagram chain has finished and every id the
    // library injects -- including the unnamespaced literals it does not
    // namespace per render -- is already in the document. Stated as the
    // spec-level property rather than as a vocabulary to reserve: it catches a
    // collision with any id, from any diagram type, in any future version of
    // the bundle, and it is the backstop for the payload-derived ids that the
    // template's `h-` prefix on heading ids cannot cover.
    deadAnchors: [...document.querySelectorAll('#toc a[data-target]')]
      .filter(a => {
        const t = document.getElementById(a.dataset.target);
        return !t || !/^H[23]$/.test(t.tagName);
      })
      .map(a => a.dataset.target),
    chips: document.querySelectorAll('.img-chip').length,
    pwn: window.__PWN === undefined ? null : window.__PWN,
    dagCaption: (document.querySelector('.dag-caption') || {}).textContent || null,
    // Anchored to .dag-caption's previous sibling, which IS the generated graph
    // box: the template inserts the box and then the caption before the same
    // anchor, so they are adjacent siblings. Selecting "the first .mermaid-block
    // whose data-src starts with flowchart" instead picks up spec.md's own
    // decorative `flowchart LR / A[Start] --> B[End]` on gate2 -- measured --
    // and reaches the real graph in the plan-region case only because that
    // fixture's own fence happens to be a sequenceDiagram.
    dagSrc: (() => {
      const cap = document.querySelector('.dag-caption');
      const box = cap && cap.previousElementSibling;
      return box && box.classList.contains('mermaid-block') ? (box.dataset.src || '') : '';
    })()
  }));
  await ctx.close();
  return { ...r, pageerrors: errs, offsite: reqs };
}

// 1. Gate 1: spec only.
{
  const f = render(join(FIX, 'spec.md'), null, join(W, 'g1.html'));
  const r = await probe(f);
  chk('gate1: no banners', r.banners, []);
  chk('gate1: pending callout rendered', r.pending, 1);
  chk('gate1: no content h1', r.contentH1, 0);
  chk('gate1: diagram in both themes', [r.light, r.dark], [1, 1]);
  chk('gate1: no offsite requests', r.offsite, []);
  chk('gate1: no page errors', r.pageerrors, []);
}

// 2. Gate 2: spec + plan. Graph must show only declared edges.
{
  const f = render(join(FIX, 'spec.md'), join(FIX, 'plan.md'), join(W, 'g2.html'));
  const r = await probe(f);
  chk('gate2: no banners', r.banners, []);
  chk('gate2: no pending callout', r.pending, 0);
  const plan = r.groups.find(g => g.h2 === 'Plan');
  chk('gate2: all three tasks under Plan', plan ? plan.kids.length : 0, 3);
  chk('gate2: dag caption present', typeof r.dagCaption === 'string', true);
  chk('gate2: spec diagram plus dag rendered', [r.light, r.dark], [2, 2]);
  // The comment above this block promised "only declared edges" while nothing
  // in the file read an edge. plan.md declares Task 2 -> Task 1 and Task 3 ->
  // Task 1, Task 99; Task 99 has no heading of its own, and the `Depends on:
  // Task 2` sitting in PROSE must not become an edge. The exact list is the
  // only form that says all three at once: a count passes with the wrong pair,
  // and a some() passes with an extra one alongside the right ones.
  chk('gate2: graph carries exactly the declared edges',
      (r.dagSrc.match(/^\s*T\d+ --> T\d+$/gm) || []).map(e => e.trim()),
      ['T1 --> T2', 'T1 --> T3']);
  chk('gate2: no page errors', r.pageerrors, []);
}

// 3. Broken diagram: one error box, the others still render.
{
  const f = render(join(FIX, 'broken-diagram.md'), null, join(W, 'broken.html'));
  const r = await probe(f);
  chk('broken: exactly one error box', r.errBoxes, 1);
  chk('broken: other diagrams still render', [r.light, r.dark], [2, 2]);
  chk('broken: no page errors', r.pageerrors, []);
}

// A spec carrying its own "## Plan" and its own task-shaped "### Task 1:" must
// not capture the sentinel, the index group, or the dependency graph. Five
// review rounds put the plan's tasks under a foreign heading; this pins it.
{
  const f = render(join(FIX, 'plan-region.md'), join(FIX, 'plan.md'), join(W, 'plan-region.html'));
  const r = await probe(f);
  // LAST matching group: plan-region.md deliberately carries its own "## Plan"
  // section, and the sentinel marker is stripped before data-toc is captured,
  // so both index groups are literally labelled "Plan".
  const plan = r.groups.filter(g => g.h2 === 'Plan').pop();
  chk('plan-region: tasks nest under Plan', plan ? plan.kids : null,
      ['Task 1: Alpha', 'Task 2: Beta', 'Task 3: Gamma']);
  chk('plan-region: spec task heading excluded from the Plan group',
      (plan ? plan.kids : []).some(k => /Example quoted/.test(k)), false);
  chk('plan-region: graph node emitted once per real task',
      (r.dagSrc.match(/^\s*T\d+\[/gm) || []).length, 3);
  // The property no static test can reach, and the reason this fixture carries a
  // sequence fence ahead of a "## Database" heading. Every index entry must still
  // resolve to its own heading after the diagrams have landed: a heading whose id
  // collides with one the library injects resolves to that node instead, silently,
  // and only when the diagram precedes it in document order. This page holds both
  // marker vocabularies -- the generated flowchart DAG and the sequence fence --
  // so it covers the whole family rather than one diagram type. Asserted HERE and
  // not in gate2, whose fixtures collide with nothing and would report [] with the
  // template's heading-id prefix deleted.
  chk('plan-region: every index entry resolves to its own heading', r.deadAnchors, []);
  chk('plan-region: no banners', r.banners, []);
  chk('plan-region: no page errors', r.pageerrors, []);
}

// 4. Inertness.
{
  const f = render(join(FIX, 'beacon.md'), null, join(W, 'beacon.html'));
  const r = await probe(f);
  chk('beacon: zero offsite requests', r.offsite, []);
  chk('beacon: remote image is a chip', r.chips, 1);
  chk('beacon: nothing executed', r.pwn, null);
  const hosts = r.anchors.map(a => a.host).filter(Boolean);
  chk('beacon: no anchor reaches a remote host', hosts, ['example.com']);
  const hrefs = r.anchors.map(a => a.href);
  chk('beacon: javascript and UNC hrefs demoted', hrefs.includes('javascript:window.__PWN=1'), false);
  chk('beacon: bare relative link kept', hrefs.includes('BLOCKS.md'), true);
  // Task 13's Critical, regression-tested in a real browser: the fence in this
  // fixture carries %%{init:{"flowchart":{"htmlLabels":true}}}%% and an <img>
  // node label. Both counts are zero only while the secure list holds.
  chk('beacon: directive cannot re-enable HTML labels', r.foreignObjects, 0);
  chk('beacon: directive cannot inject CSS into the emitted stylesheet', r.styleBeacons, 0);
  chk('beacon: no orphaned mermaid temp container', r.orphans, 0);
  chk('beacon: both directive fences still rendered in both themes', [r.light, r.dark], [2, 2]);
  chk('beacon: the run completed rather than stalling', r.diagramsState, 'done');
}

// 5. Dangling comment: content survives, nothing is lost.
{
  const f = render(join(FIX, 'comment-truncation.md'), null, join(W, 'ct.html'));
  const r = await probe(f);
  chk('comment: no content-lost banner', r.banners.filter(b => b.startsWith('Content lost')), []);
  chk('comment: later section survived', r.groups.some(g => g.h2 === 'Later Section'), true);
  chk('comment: pending callout survived', r.pending, 1);
}

// 6. Hostile title never becomes markup.
{
  const f = render(join(FIX, 'hostile-title.md'), null, join(W, 'ht.html'));
  const r = await probe(f);
  chk('hostile: no banners', r.banners, []);
  chk('hostile: no page errors', r.pageerrors, []);
}

await browser.close();
// Last, on the only path that reaches the summary: a block that threw never
// arrives here at all, which is louder still.
if (pass + fail !== EXPECTED) {
  no(`assertion inventory: ran ${pass + fail}`, `expected ${EXPECTED}`);
}
console.log(`\nbrowser: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
```

Four things in this file are not obvious from reading it.

**The launcher** is a two-candidate resolver rather than a single `chromium.launch({ channel: 'chrome' })`, because `channel: 'chrome'` requires a *system Google Chrome* from a manifest that declares `playwright-core` — and the browser most machines with playwright-core actually have is the managed build from `npx playwright install chromium`. Both are tried, managed build first because it is version-pinned to the manifest and so makes a run here mean the same as a run anywhere. Neither is guaranteed, so exhausting both prints a skip line naming what was tried and how to fix it, and exits 2 — a third status, because a skip that exited 0 reads as a pass to anything checking only the status.

**The canary** runs before the browser launches, and it is the only thing standing between this file and its worst failure mode. Every assertion here is worth exactly what `chk` is worth; rewriting `chk` to `(m, got, want) => ok(m)` is one line that changes no pinned selector and no source count. Measured, so neutered: the harness certified a page firing four live requests to `evil.example.invalid` as `browser: 38 passed, 0 failed`, with the shell suite green beside it. The canary reports by **throwing**, never through `no()` — reporting through `no()` would survive `chk` being neutered but go silent the moment `no()` is itself the broken part, and "the reporting path can be trusted" is the whole proposition being established, so the check may not lean on any part of it. It exercises both directions, which also catches a `chk` stubbed to always fail, and a neutered `ok()` or `no()`; each variant names which direction broke. Its two `chk` calls restore the counters afterwards, so the suite is 38 assertions while the file holds 40 `chk(` call sites — the two numbers are *meant* to differ by exactly two, and Step 1 pins both so that adding or removing a real assertion has to move both.

**`EXPECTED` and the inventory check** are the runtime half of the shell's source-count pin, and they are different guarantees. The shell counts the `chk(` calls the file *contains*; this counts the ones it *runs*. Wrapping an assertion block in `if (false)` changes neither the source count nor any pinned selector — measured, it reported `browser: 26 passed, 0 failed`, exit 0, with eleven assertions silently gone. All three of the constant, its use, and the source count are pinned in Step 1, because pinning any two leaves the third free.

**`dagSrc` is anchored to `.dag-caption`'s previous sibling**, which is the generated graph box — the template inserts box then caption before the same anchor, so they are adjacent. The obvious selector, "the first `.mermaid-block` whose `data-src` starts with `flowchart`", resolves on gate 2 to `spec.md`'s own decorative `flowchart LR / A[Start] --> B[End]`, not to the graph; it reaches the real graph in the `plan-region` case only because that fixture's own fence happens to be a `sequenceDiagram`. The gate 2 comment has claimed "only declared edges" since this task was written while nothing in the file read an edge, and an edge assertion built on the unanchored selector would have asserted against the wrong diagram.

**A known, deliberate limit.** Neither the shell block nor the canary detects an assertion rewritten to compare a value to itself — `chk(m, r.offsite, r.offsite)`. The source count is unchanged, every selector still resolves, `chk` still genuinely compares, and the assertion still executes, so the runtime inventory counts it. Measured: three assertions so rewritten leave a clean run at `38 passed, 0 failed` and degrade the gutted-`secure`-list control from `35 passed, 3 failed` to `36 passed, 2 failed` — detection erodes rather than vanishing, which is why it is tolerated. Closing it needs per-call-site pinning of every expected value, which was weighed and declined: it would churn on every ordinary edit for a mutation nothing plausible produces by accident.

- [ ] **Step 4: Run the test to verify it passes**

Expected: all twelve browser-harness assertions PASS. Confirm the whole suite is green and exits 0:

```bash
bash assets/change-brief/tests/render_test.sh; echo "exit=$?"
```
Expected, measured: `shell: 290 passed, 0 failed`, `exit=0`.

Then run the harness itself. `npm install` needs network once; the browser does not have to be downloaded if the machine already has Google Chrome:

```bash
cd assets/change-brief/tests/browser && npm install && node verify.mjs; echo "exit=$?"
```
Expected, measured against the real fixtures on Google Chrome 150 (the managed chromium was absent — the local cache held revision 1228 and playwright-core 1.62.1 asks for 1234, so the resolver fell through to the system Chrome): `browser: 38 passed, 0 failed`, `exit=0`.

That green is only meaningful because the assertions were shown to discriminate. Measured, against mutated copies of `template.html` supplied through `BRIEF_TEMPLATE` so no repo file was touched:

- Gutting the mermaid `secure` list to `["secure","securityLevel","startOnLoad"]` gives `35 passed, 3 failed`: `beacon: zero offsite requests` collects four live requests to `evil.example.invalid`, `directive cannot re-enable HTML labels` counts 6 `<foreignObject>`, and `directive cannot inject CSS into the emitted stylesheet` counts 2 payload-bearing `<style>` elements.
- Removing the `h-` prefix from `slug()` gives `37 passed, 1 failed`: `deadAnchors` reports `["database"]`.
- Injecting a `setTimeout(() => __definitely_not_defined__(), 0)` gives `33 passed, 5 failed`, one per page-error assertion.

These are Task 13, Task 14 and Task 15 properties that had never been executed in a browser before this task.

If no browser can be found the run exits 2 with a skip line — walk cases 1-11 cover the same ground by hand. The temporary render directory is reaped on every exit path: pass, assertion failure, a throw out of `render()`, the canary's throw, and the no-browser skip.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/tests/browser/
git commit -m "test(change-brief): optional headless smoke test with its own manifest"
```

---

### Task 18: `BLOCKS.md` block catalog — `static-verifiable`

**Depends on:** Task 6

The catalog is the only surface the authoring agent reads. It must be self-contained: an agent that reads `BLOCKS.md` and never opens the spec still authors a correct document.

**Files:**
- Create: `assets/change-brief/BLOCKS.md`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== BLOCKS.md =="
B="$S/BLOCKS.md"
[ -r "$B" ] && ok "BLOCKS.md present" || no "BLOCKS.md present" "missing"
for n in $(seq 1 27); do
  if grep -qE "^\| $n \|" "$B" 2>/dev/null; then ok "block $n catalogued"
  else no "block $n catalogued" "missing"; fi
done
chk "27 catalog rows" "$(grep -cE '^\| [0-9]+ \|' "$B" 2>/dev/null || echo 0)" "27"
# Both pins below were bare `grep -q` substrings until a mutant measured them.
# `render.sh` occurs 5 times in the catalog and `Depends on:` 3 times, but only
# 2 and 1 of those sit in the sections the labels name -- so a BLOCKS.md with
# the whole `## Rendering a brief` section AND the `**Depends on:**` placement
# rule deleted, 29 lines and a quarter of the file gone including every render
# command, still reported 321 passed, 0 failed. Each now anchors on the section
# heading at line start and on the exact text carrying the rule. Concatenated,
# not summed: a sum still totals right with one term at zero and another at two.
chk "  documents both render gates under their own heading" \
  "$(grep -cE '^## Rendering a brief$' "$B" 2>/dev/null)$(grep -cF '"$BRIEF_DIR/render.sh" docs/specs/<name>.md -o docs/briefs/' "$B" 2>/dev/null)$(grep -cF '"$BRIEF_DIR/render.sh" docs/specs/<name>.md docs/plans/<name>.md -o docs/briefs/' "$B" 2>/dev/null)" "111"
chk "  documents the Depends on placement rule and its none case" \
  "$(grep -cF 'first thing in its own paragraph' "$B" 2>/dev/null)$(grep -cF 'Write `none` when a task is independent' "$B" 2>/dev/null)" "11"
# Task 18's premise is that an agent reading only this file authors correctly.
# The catalog named the two walk tags in blocks 8 and 25 and the Inventory in
# block 27 and defined none of the three: an agent knew the tags existed, could
# not choose between them, and could not write a case. Anchored on the two
# definition bullets themselves, not on the tag names -- those also appear in
# three table rows and a badge row, none of which define anything.
chk "  defines both walk tags and the Inventory case rule" \
  "$(grep -cE '^- `static-verifiable` — ' "$B" 2>/dev/null)$(grep -cE '^- `browser-walk-only` — ' "$B" 2>/dev/null)$(grep -cF 'at least one case per `browser-walk-only` task' "$B" 2>/dev/null)" "111"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: FAILs for the missing catalog, exit 1.

- [ ] **Step 3: Write the catalog**

Create `assets/change-brief/BLOCKS.md`:

````markdown
# Change Brief Block Catalog

Authoring reference for `umbrella:brainstorming` (spec blocks) and
`umbrella:writing-plans` (plan blocks). Include only the blocks that apply —
**an empty section is worse than an absent one.**

## Heading convention

Section headings are **unnumbered** `##`. `render.sh` synthesizes a `## Plan`
heading, so any fixed numbering collides or misorders as soon as a document has
a different section count.

Canonical spec sections: `Why this change`, `Existing system`, `Design`,
`Requirements`, `Testing strategy`, and optionally `Out of scope`.
Canonical plan sections: the tasks as `###`, plus `## Browser-Walk Inventory`.

Write exactly one H1, on line 1. `render.sh` strips it — the spec's title
becomes the masthead. Any H1 further down is flattened to `####`.

## Spec blocks — always present

| # | Block |
|---|---|
| 1 | Motivation / trigger |
| 2 | Success criteria |
| 3 | Non-goals |
| 4 | Code inventory table — path → responsibility → change |
| 5 | Persona × surface × affordance matrix |
| 6 | Target-state architecture (`flowchart`) |
| 7 | File structure — create / modify / delete |
| 8 | Requirements, each tagged `static-verifiable` or `browser-walk-only` |
| 9 | Testing strategy |

## Spec blocks — include when applicable

| # | Block | Applies when |
|---|---|---|
| 10 | Alternatives rejected | more than one approach was seriously considered |
| 11 | Current-state diagram (`flowchart`) | change touches an existing multi-component flow |
| 12 | Current call/data-flow trace (`sequenceDiagram`) | change alters an existing runtime interaction |
| 13 | Known constraints / gotchas | existing code or platform imposes non-obvious limits |
| 14 | Runtime interaction (`sequenceDiagram`) | new behavior spans two or more actors |
| 15 | Integration delta (`flowchart` + `classDef`) | new components attach to existing ones |
| 16 | New types/classes (`classDiagram`) | change introduces types or classes |
| 17 | Data model (`erDiagram`) + migrations | change alters persisted schema |
| 18 | API / contract surface table | change adds or alters an interface others call |
| 19 | State machine (`stateDiagram-v2`) | change introduces states with transition rules |
| 20 | Infra changes — services, env vars, deploy | change touches infrastructure or configuration |
| 21 | Failure modes table | change has non-trivial failure paths |
| 22 | Rollback plan | change is not trivially revertible |
| 23 | Out of scope / deferred | adjacent work is knowingly deferred and would otherwise be assumed in scope. Distinct from block 3: Non-goals say what this change will never do; block 23 names work that is real but sequenced later. |

## Plan blocks — always present

| # | Block |
|---|---|
| 24 | Tasks with steps and `- [ ]` checkboxes |
| 25 | Walk tag per task |
| 26 | `**Depends on:**` per task (`none` when independent) |
| 27 | Browser-Walk Inventory |

The task dependency graph is **not** an agent-authored block. The renderer
derives it from block 26.

## Walk tags and the Inventory

Blocks 8 and 25 tag every requirement and every task with exactly one of two
words. The deciding property is **what it would take to prove the thing true**:

- `static-verifiable` — an assertion in `tests/render_test.sh`, or static
  inspection of the repo, can prove it.
- `browser-walk-only` — proving it means a person opening the rendered page in
  a real browser and looking: paint, legibility, layout, print, cross-browser
  parity. An optional headless smoke test may cover some of these but never
  converts the tag; where it cannot run, its assertions fall back to the walk.

**A >90 review does not clear the `browser-walk-only` class — the walk does.**

Block 27 is where those tasks are discharged. `## Browser-Walk Inventory` is a
numbered list holding **at least one case per `browser-walk-only` task**. Each
case is plain prose in full sentences: a bold title, the command that produces
the artifact or the file to open, the conditions to set up (viewport, theme,
network state), and what to confirm. Every case opens a local file — no account
and no login anywhere. Record pass or fail per case.

## Markdown conventions

| You write | The renderer paints |
|---|---|
| `##` / `###` headings | collapsible index, sections with nested subsections, scrollspy |
| ` ```mermaid ` fence | diagram, pre-rendered in both light and dark |
| markdown table | styled table, scrollable inside its own container |
| `- [ ]` / `- [x]` | checkbox; per-task progress bar appended to the `###` heading |
| `` `static-verifiable` `` / `` `browser-walk-only` `` in a heading | colored badge, amber for walk-only |
| `> [!NOTE]` / `[!WARNING]` / `[!IMPORTANT]` / `[!TIP]` / `[!CAUTION]` | colored callout |
| `classDef` inside a mermaid fence | new-vs-existing color coding |
| `**Depends on:** Task 3, Task 5` | edge in the renderer-built task dependency graph |

`**Depends on:**` must be the **first thing in its own paragraph**, directly
under the task heading. Write `none` when a task is independent. A mention
inside prose or a code fence is ignored, by design.

## Not available to you

- **Raw HTML** — escaped and shown as text, never executed.
- **Remote images** — rendered as an inert chip. Only `data:image/*` embeds.
- **Links** — only `http(s):`, `mailto:`, relative paths, and `#fragment`
  survive. `javascript:`, `data:`, `vbscript:` and protocol-relative `//host`
  render as plain text.

The brief is opened by people with no repo, often from an email attachment. It
must not phone home or execute anything. The guarantee is **zero network
requests on load**.

## Rendering a brief

```bash
# Spec gate — no plan argument
"$BRIEF_DIR/render.sh" docs/specs/<name>.md -o docs/briefs/<name>.html

# Plan gate — both sources
"$BRIEF_DIR/render.sh" docs/specs/<name>.md docs/plans/<name>.md -o docs/briefs/<name>.html
```

`$BRIEF_DIR` is `<announced skill base directory>/../../assets/change-brief`.
`${CLAUDE_PLUGIN_ROOT}` is **not** set in the Bash tool environment — it works
in `hooks.json` only, because the harness substitutes it before spawning the
hook process.

Check `[ -x "$BRIEF_DIR/render.sh" ]` first. **If the assets cannot be found,
report it and continue the review on the markdown. A missing renderer must
never block the review gate.**

`docs/briefs/` is derived output and belongs in the consumer project's
`.gitignore`. If it is absent, add it.

Executing subagents read `docs/plans/*.md`. They never read `docs/briefs/*.html`.
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: all BLOCKS.md assertions PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add assets/change-brief/BLOCKS.md assets/change-brief/tests/render_test.sh
git commit -m "feat(change-brief): 27-block authoring catalog with conventions and render command"
```

---

### Task 19: Hook the brainstorming skill — `static-verifiable`

**Depends on:** Task 18

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== brainstorming skill hooks =="
BS="$R/skills/brainstorming/SKILL.md"
grep -q 'BLOCKS.md' "$BS" && ok "step 7 points at the block catalog" \
  || no "step 7 points at the block catalog" "missing"
grep -q '9b' "$BS" && ok "step 9b renders the brief" || no "step 9b renders the brief" "missing"
chk "render brief node in the dot graph" "$(grep -c 'Render brief' "$BS")" "3"
grep -q 'never block the review gate' "$BS" && ok "degradation rule present" \
  || no "degradation rule present" "missing"
grep -q 'never read' "$BS" && ok "executing subagents rule present" \
  || no "executing subagents rule present" "missing"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: five FAILs, exit 1.

- [ ] **Step 3a: Update the checklist**

In `skills/brainstorming/SKILL.md`, replace checklist item 7 with:

```markdown
7. **Write design doc** — save to `docs/specs/YYYY-MM-DD-<topic>-design.md` and commit. Author it with the block catalog at `$BRIEF_DIR/BLOCKS.md`, unnumbered `##` sections, including only the blocks that apply
```

Insert a new item between 9 and 10:

```markdown
9b. **Render the change brief** — `"$BRIEF_DIR/render.sh" <spec> -o docs/briefs/<name>.html` with no plan argument. If the assets cannot be found, say so and continue on the markdown — a missing renderer must never block the review gate
```

Replace checklist item 10 with:

```markdown
10. **User reviews the rendered brief** — point the user at `docs/briefs/<name>.html` and state plainly that altering the feature is free at this point
```

- [ ] **Step 3b: Update the process-flow graph**

In the `dot` graph, add the node declaration after `"Adversarial review >90?" [shape=diamond];`:

```dot
    "Render brief" [shape=box];
```

and replace the edge `"Adversarial review >90?" -> "User reviews spec?" [label="yes"];` with:

```dot
    "Adversarial review >90?" -> "Render brief" [label="yes"];
    "Render brief" -> "User reviews spec?";
```

- [ ] **Step 3c: Update the User Review Gate prose**

Replace the quoted prompt under `**User Review Gate:**` with:

```markdown
> "Spec written and committed to `<path>`, and rendered to `<brief path>`. Open the brief in your browser and review it — the index on the left navigates sections, and diagrams are rendered inline. **Changing the shape of this feature costs nothing right now**; after the plan is written the same change costs a plan rewrite. Let me know if you want changes before we start the implementation plan."
```

- [ ] **Step 3d: Add the asset resolution note**

Append a new section before `## Key Principles`:

```markdown
## Change Brief Assets

`$BRIEF_DIR` is `<the skill base directory announced when this skill loads>/../../assets/change-brief`.
`${CLAUDE_PLUGIN_ROOT}` is **not** set in the Bash tool environment — it is
substituted by the harness for `hooks.json` only.

Verify `[ -x "$BRIEF_DIR/render.sh" ]` before use. **If the assets cannot be
found, report it and proceed with markdown review. A missing renderer must
never block the review gate.**

`docs/briefs/` is derived output and belongs in the consumer project's
`.gitignore`. If it is absent, add it.

Executing subagents read `docs/plans/*.md`. They never read `docs/briefs/*.html`.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: five PASSes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/brainstorming/SKILL.md assets/change-brief/tests/render_test.sh
git commit -m "feat(brainstorming): render a change brief before the user review gate"
```

---

### Task 20: Hook the writing-plans skill — `static-verifiable`

**Depends on:** Task 18

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== writing-plans skill hooks =="
WP="$R/skills/writing-plans/SKILL.md"
grep -q '\*\*Depends on:\*\*' "$WP" && ok "task template carries Depends on" \
  || no "task template carries Depends on" "missing"
grep -q 'render.sh' "$WP" && ok "renders the brief after the plan gate" \
  || no "renders the brief after the plan gate" "missing"
grep -q 'never read' "$WP" && ok "executing subagents rule present" \
  || no "executing subagents rule present" "missing"
grep -q 'referenced task exist' "$WP" && ok "self-review checks dangling refs" \
  || no "self-review checks dangling refs" "missing"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: four FAILs, exit 1.

- [ ] **Step 3a: Add `**Depends on:**` to the Task Structure template**

In `skills/writing-plans/SKILL.md`, in the Task Structure code block, insert directly beneath the task heading line:

```markdown
### Task N: [Component Name]  — `static-verifiable` | `browser-walk-only`

**Depends on:** Task A, Task B   <!-- or `none` -->

**Files:**
```

- [ ] **Step 3b: Note the H1 interaction**

Append to the `## Plan Document Header` section:

```markdown
Keep the `# … Implementation Plan` H1. `render.sh` strips it when building the
change brief so the merged document has exactly one H1 — this is documented so
nobody "fixes" the H1 away.
```

- [ ] **Step 3c: Add the render step and the brief path**

Replace the `## Adversarial Plan Review (Umbrella gate)` section's closing line with:

````markdown
Dispatch a fresh subagent to adversarially review the plan using `skills/writing-plans/plan-document-reviewer-prompt.md`. Iterate until it scores **>90** before execution handoff.

## Render the Change Brief

Once the plan review passes, re-render the brief with both sources:

```bash
"$BRIEF_DIR/render.sh" docs/specs/<name>.md docs/plans/<name>.md -o docs/briefs/<name>.html
```

`$BRIEF_DIR` is `<announced skill base directory>/../../assets/change-brief`.
`${CLAUDE_PLUGIN_ROOT}` is not set in the Bash tool environment. Verify
`[ -x "$BRIEF_DIR/render.sh" ]` first — **if the assets cannot be found, report
it and continue on the markdown. A missing renderer must never block the gate.**

Executing subagents read `docs/plans/*.md`. They never read `docs/briefs/*.html`.
````

Then in `## Execution Handoff`, change the first line to:

```markdown
**"Plan complete and saved to `docs/plans/<filename>.md`, rendered to `docs/briefs/<filename>.html`. Two execution options:**
```

- [ ] **Step 3d: Extend Self-Review**

Add a fifth numbered check to `## Self-Review`:

```markdown
**5. Dependency declarations (Umbrella):** Does every task carry a `**Depends on:**` line as the first paragraph under its heading? Does every referenced task exist? Is the dependency set acyclic?
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: four PASSes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/writing-plans/SKILL.md assets/change-brief/tests/render_test.sh
git commit -m "feat(writing-plans): Depends on declarations and brief render after the plan gate"
```

---

### Task 21: Extend both reviewer prompts — `static-verifiable`

**Depends on:** Task 18

Both SKILL.md files already gate on `>90` while neither prompt's output format defines a score — a pre-existing inconsistency that block-coverage penalties would otherwise have nothing to attach to.

**Files:**
- Modify: `skills/brainstorming/spec-document-reviewer-prompt.md`
- Modify: `skills/writing-plans/plan-document-reviewer-prompt.md`

- [ ] **Step 1: Write the failing test**

Append to `assets/change-brief/tests/render_test.sh`, before the final `echo`:

```bash
echo "== reviewer prompts =="
SP="$R/skills/brainstorming/spec-document-reviewer-prompt.md"
PP="$R/skills/writing-plans/plan-document-reviewer-prompt.md"
grep -q 'Score:' "$SP" && ok "spec prompt has a Score field" || no "spec prompt has a Score field" "missing"
grep -q 'Score:' "$PP" && ok "plan prompt has a Score field" || no "plan prompt has a Score field" "missing"
grep -q 'blocks 1-23' "$SP" && ok "spec prompt scoped to blocks 1-23" \
  || no "spec prompt scoped to blocks 1-23" "missing"
chk "spec prompt does not grade plan blocks" "$(grep -c 'must not penalize' "$SP")" "1"
grep -q 'acyclic' "$PP" && ok "plan prompt checks acyclicity" || no "plan prompt checks acyclicity" "missing"
grep -q 'Browser-Walk Inventory' "$PP" && ok "plan prompt checks the inventory" \
  || no "plan prompt checks the inventory" "missing"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: six FAILs, exit 1.

- [ ] **Step 3a: Extend the spec reviewer prompt**

In `skills/brainstorming/spec-document-reviewer-prompt.md`, add a row to the What to Check table:

```markdown
    | Block coverage | Spec blocks 1-23 from `assets/change-brief/BLOCKS.md` — see below |
```

Add before `## Calibration`:

```markdown
    ## Block Coverage

    Grade against **spec blocks 1-23 only**. Penalize a missing always-present
    block (1-9). Penalize a change that touches infrastructure with no block 20,
    introduces types with no block 16, alters persisted schema with no block 17,
    adds a called interface with no block 18, or introduces states with no
    block 19.

    You must not penalize the absence of plan blocks 24-27. A spec at the first
    gate cannot contain them.
```

Replace the Output Format block with:

```markdown
    ## Spec Review

    **Score:** <integer 0-100>

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Section X]: [specific issue] - [why it matters for planning]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

- [ ] **Step 3b: Extend the plan reviewer prompt**

In `skills/writing-plans/plan-document-reviewer-prompt.md`, add a row to the What to Check table:

```markdown
    | Plan blocks | Blocks 24-27 from `assets/change-brief/BLOCKS.md` — see below |
```

Add before `## Calibration`:

```markdown
    ## Plan Block Coverage

    Grade against **plan blocks 24-27 only**:

    - **24** — every task has steps with `- [ ]` checkboxes.
    - **25** — every task carries a `static-verifiable` or `browser-walk-only` tag.
    - **26** — every task carries a `**Depends on:**` line as the first paragraph
      under its heading. Every referenced task must exist, and the dependency set
      must be acyclic. Report dangling references and cycles by task number.
    - **27** — a `## Browser-Walk Inventory` exists with at least one numbered,
      plain-prose case per `browser-walk-only` task.
```

Replace the Output Format block with:

```markdown
    ## Plan Review

    **Score:** <integer 0-100>

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Task X, Step Y]: [specific issue] - [why it matters for implementation]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/render_test.sh`
Expected: six PASSes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/brainstorming/spec-document-reviewer-prompt.md skills/writing-plans/plan-document-reviewer-prompt.md assets/change-brief/tests/render_test.sh
git commit -m "feat(reviewers): numeric Score field and per-document block coverage"
```

---

### Task 22: Verify `$BRIEF_DIR` resolution on a real plugin install — `static-verifiable`

**Depends on:** Task 19, Task 20

This is the single highest-leverage failure point in the change: if resolution is wrong, both gates emit a command that fails. It cannot be verified from the repo working tree — only from an installed plugin, where the skill base directory is `~/.claude/plugins/cache/umbrella/umbrella/<version>/skills/<name>`.

**Files:**
- Create: `assets/change-brief/tests/resolve_test.sh`

- [ ] **Step 1: Write the failing test**

Create `assets/change-brief/tests/resolve_test.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash assets/change-brief/tests/resolve_test.sh`
Expected: either `SKIP` (plugin not installed yet) or FAILs because the installed copy predates this change.

- [ ] **Step 3: Reinstall the plugin and confirm**

Reinstall umbrella from this working tree so the cache carries `assets/change-brief/`. Then confirm the assets landed:

```bash
CACHE="$HOME/.claude/plugins/cache/umbrella/umbrella"
ls -d "$CACHE"/*/assets/change-brief/render.sh
```
Expected: the path prints. If it does not, the plugin package does not ship `assets/` — add it to whatever manifest or packaging step controls the plugin payload, then reinstall.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash assets/change-brief/tests/resolve_test.sh`
Expected: `resolve: 7 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
chmod +x assets/change-brief/tests/resolve_test.sh
git add assets/change-brief/tests/resolve_test.sh
git commit -m "test(change-brief): verify BRIEF_DIR resolution from an installed plugin"
```

---

### Task 23: Dogfood render and full browser walk — `browser-walk-only`

**Depends on:** Task 16, Task 17, Task 21, Task 22

The first dogfood case is this change itself. Render the spec and this plan, and the brief you read to accept the work is produced by the work.

**Files:**
- Create: `docs/briefs/2026-07-27-visual-change-briefs-design.html` (gitignored)

- [ ] **Step 1: Run the full static suite**

Run:
```bash
bash assets/change-brief/tests/render_test.sh; echo "exit=$?"
bash assets/change-brief/tests/resolve_test.sh; echo "exit=$?"
```
Expected: both report `0 failed` and `exit=0`.

- [ ] **Step 2: Run the headless smoke test if available**

Run:
```bash
cd assets/change-brief/tests/browser && npm install && node verify.mjs; echo "exit=$?"
```
Expected: `browser: N passed, 0 failed`, `exit=0`. If playwright-core cannot be installed, record that it was skipped and rely on the walk cases below.

- [ ] **Step 3: Render the dogfood brief**

Run:
```bash
assets/change-brief/render.sh \
  docs/specs/2026-07-27-visual-change-briefs-design.md \
  docs/plans/2026-07-30-visual-change-briefs.md \
  -o docs/briefs/2026-07-27-visual-change-briefs-design.html
```
Expected: the output path on stdout, **nothing on stderr**. Any `warning:` line means the sources have a structural defect — fix the source, do not suppress the warning.

- [ ] **Step 4: Execute the Browser-Walk Inventory**

Work through all eleven cases below in a real browser and record the result of each. **This is the mandatory gate.** A >90 plan review does not clear the `browser-walk-only` class — the walk does.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(change-brief): dogfood render and completed browser walk"
```

---

## Browser-Walk Inventory

Eleven cases. Nine are carried forward from the spec's `browser-walk-only` requirements; cases 10 and 11 were added by Task 13 to settle consequences that task states but cannot verify statically. No account or login is involved anywhere — every case opens a local file. Execute each in full sentences and record pass or fail.

1. **Index navigation.** Open `docs/briefs/2026-07-27-visual-change-briefs-design.html` from `file://` in Chrome at a 1440px-wide window. Confirm the left sidebar lists every `##` section of the document as a top-level entry, with each of that section's `###` subsections nested beneath it. Click a chevron next to one group and confirm it collapses that group's children without navigating away from the current scroll position. Confirm the Plan group lists all twenty-three tasks as children, not just the first few. Click one entry in the Plan group and confirm the page lands on that task's own heading — this is the only check anywhere that a heading id still resolves to its heading after the diagrams have injected their own ids, and it is what would surface a collision the `h-` prefix does not cover. Then scroll slowly from the top of the document to the bottom and confirm the index highlight never goes blank — not while you are deep inside a long section with no heading anywhere near the top of the viewport, and not at the very end of the document. Expect it to follow the section you are reading, but do not record lag as a failure, because the geometry does not promise it: the highlight only moves when a heading crosses the top 30% of the viewport, so a final heading with less than roughly two thirds of a viewport of content after it can never become active at all and the previous entry stays lit, and a jump straight to an anchor the page cannot scroll into that band fires no update either. What must never happen, on any of those paths, is no entry highlighted at all.

2. **Theme switching.** With the same page open, click the theme control in the sidebar header through all three states: auto, light, and dark. In each state confirm every mermaid diagram remains legible — specifically that no diagram shows dark text on a dark background or light text on a light background. Reload the page and confirm the theme you last selected is still in effect.

3. **Narrow viewport.** Resize the browser window to 480px wide. Confirm the sidebar is no longer visible as a column and a hamburger toggle appears at the top left. Click the toggle and confirm the sidebar slides over the content rather than squeezing it. Scroll the full length of the document and confirm no table, diagram, or code block forces the page body to scroll horizontally.

4. **Broken diagram isolation.** Edit `assets/change-brief/tests/fixtures/broken-diagram.md` if needed so it contains one deliberately invalid mermaid fence between two valid ones. Render it with `assets/change-brief/render.sh assets/change-brief/tests/fixtures/broken-diagram.md -o /tmp/broken.html` and open the result. Confirm a red error box appears in place of the invalid diagram, that the box shows the parse message and the offending source text, and that both valid diagrams on either side of it still render normally.

5. **Print from dark theme.** Return to the dogfood brief, switch the theme control to dark, then open the browser's print preview. Confirm the sidebar and theme control are absent from the printed output, that the page background is white with black text rather than the dark theme, that diagrams appear in their light-rendered variant rather than as dark boxes, and that no diagram is split across a page break.

6. **Inertness with the network disabled.** Render the beacon fixture with `assets/change-brief/render.sh assets/change-brief/tests/fixtures/beacon.md -o /tmp/beacon.html`. Disable the browser's network access, open the developer console and the network tab, then load `/tmp/beacon.html`. Confirm the network tab shows zero requests to any host, that no script error or `__PWN` variable appears in the console, that the remote image is displayed as a bordered inert chip showing its URL rather than as an image, that the `javascript:` link is plain text rather than a clickable link, and that the `/\evil.example.invalid/share` link is likewise plain text. Confirm the `BLOCKS.md`, `#design`, and `https://example.com/` links are still real links.

7. **Dependency graph correctness.** Render the plan fixture with `assets/change-brief/render.sh assets/change-brief/tests/fixtures/spec.md assets/change-brief/tests/fixtures/plan.md -o /tmp/dag.html` and open it. Confirm a dependency graph appears immediately above the first task heading inside the Plan section, not elsewhere in the document. Confirm the graph shows exactly two edges — Task 1 to Task 2 and Task 1 to Task 3. Confirm there is no edge from Task 2 to Task 3 despite Task 3's prose mentioning the literal string `Depends on: Task 2`, no node for the nonexistent Task 99, and no edge originating from Task 1's `none` declaration. Confirm Task 2 is colored amber as a `browser-walk-only` task.

8. **Pending notice at the spec gate.** Render the spec alone with `assets/change-brief/render.sh docs/specs/2026-07-27-visual-change-briefs-design.md -o /tmp/gate1.html` and open it. Scroll to the Plan section and confirm it reads unmistakably as "the plan does not exist yet" — a dashed, tinted callout headed "Plan not yet written" that explicitly says changing the shape of the feature costs nothing right now. Confirm it does not read as an empty or truncated section, and confirm no red banner appears anywhere on the page.

9. **Cross-browser rendering.** Open the dogfood brief from `file://` in Firefox and again in Safari. In each, confirm the page renders equivalently to Chrome: the sidebar index is populated, every diagram is visible, the theme toggle switches themes, and no red integrity banner appears. Note any rendering difference that would mislead a reviewer.

10. **HTML in a heading, through the mermaid label path.** This case exists to settle the inferred half of Task 13's `htmlLabels` reasoning, which no static test can reach. Write a two-task fixture — two tasks so a dependency graph is drawn at all — whose first heading carries an image tag: `### Task 1: probe <img src=https://evil.example.invalid/x.png>`, with `### Task 2: second` and a `**Depends on:** Task 1` under it. Render it with `assets/change-brief/render.sh`. Open the developer console and the network tab **before** loading the file, leave the network enabled, then open the rendered brief from `file://`. The `.invalid` TLD never resolves, so a request attempt is visible in the network tab without anything leaving the machine. Confirm the network tab shows zero requests, and no attempt, to `evil.example.invalid` or any other host. Inspect the graph's first node in the elements panel and confirm its label is an SVG `<text>` element holding the tag as literal characters — no `<foreignObject>`, and no `<img>` element anywhere inside the diagram. Then remove `flowchart: { htmlLabels: false }` from `mermaid.initialize` in `assets/change-brief/template.html`, re-render, and reload with the network tab open. Under jsdom that configuration produced a `<foreignObject>` label and a live `<img>` element carrying the payload's URL, which DOMPurify did **not** strip — but every observation behind that is jsdom's, and this case is the browser's. Confirm whether the browser agrees on the DOM: `<foreignObject>` present, `<img>` present, its `src` intact. Then, separately, record whether a request attempt to `evil.example.invalid` appears in the network tab — that is the step no harness has been able to observe at all, and the one genuinely open question here. Restore the setting afterwards. Report both answers; they are what Task 13's prose is waiting on.

    **Third leg — the payload-directive route, against the template exactly as shipped.** The A/B above modifies the template; this leg modifies nothing, and it is the one that matters most, because the A/B could never have caught the bypass Task 13 now guards: a payload directive needs no template change at all, so removing `htmlLabels: false` and putting it back only ever exercised the half of the control that was never the weak one. Render `assets/change-brief/tests/fixtures/beacon.md`, which carries two directive fences — one re-enabling `htmlLabels` with an `A["<img src=https://evil.example.invalid/x.png>"]` node label, and one setting `themeCSS` to an `@font-face` plus a rule that uses it — and open it with the network tab already recording. Confirm **both** diagrams render in **both** themes; that the elements panel shows no `<foreignObject>` and no `<img>` anywhere on the page; that no `<style>` element on the page contains `evil.example.invalid`; that no `<div id="dmmd-…">` is left behind in `<body>`; that `document.documentElement.dataset.diagrams` reads `done` rather than being absent; and that no request, and no request *attempt*, to `evil.example.invalid` appears.

    The `themeCSS` half is the one to take seriously, because it is the one that got through a round of review that had already closed the other: it needs no `htmlLabels`, produces no `<foreignObject>` and no `<img>`, and leaves the diagram rendering normally, so every check aimed at the first fence reads clean while it is wide open. It is also where the browser is most needed. Under jsdom the payload is demonstrably in a live, `isConnected` `<style>` without the `secure` list and demonstrably absent with it — but whether an `@font-face` at that position actually fetches is a question jsdom cannot answer, and the ordering matters: mermaid's own theme rules always precede the payload, so a payload `@import` lands mid-stylesheet where the CSS spec says it must be ignored, while `@font-face` has no such restriction. Record which of the two, if either, produces a request.

11. **Duplicate unnamespaced ids across the two theme variants.** Mermaid does not namespace every id it emits per render — `arrowhead`, `crosshead`, `sequencenumber`, `clock` and `database` are emitted verbatim — so a page holding both a light and a dark render of one diagram holds two elements sharing each of those ids. **Confirmed:** the DOM fact. On the real dogfood brief there are 55 duplicated ids, and both the `.d-light` and the `.d-dark` slot carry their own `<marker id="arrowhead">`. **Inferred, and observed by nothing:** the visual consequence. A fragment reference such as `url(#arrowhead)` resolves to the first match in document order — the light render's marker — so the dark diagram should be painting its arrowheads in light-theme colours. That follows from the DOM plus the CSS; jsdom cannot settle it, because it paints nothing. Render a fixture containing a `sequenceDiagram` fence (arrowheads and sequence numbers are the markers this reaches), switch the theme control to dark, and confirm whether the arrowheads and sequence numbers are visible and correctly coloured against the dark background. Repeat in light. If dark is wrong, the light-before-dark render order is the cause — and the fix is to namespace the ids per pass, **not** to reverse the order, which would merely move the same defect onto print, which forces `.d-light`. Record what you actually see, not what this paragraph predicts.

---

## Self-Review

**Spec coverage.** Every `static-verifiable` requirement in the spec maps to an assertion in `assets/change-brief/tests/render_test.sh` created by Tasks 1-21. Every `browser-walk-only` requirement maps to a numbered walk case above. The six Known open findings map to Task 15. Asset path resolution maps to Task 22.

**Placeholder scan.** No "TBD", no "implement later", no "add error handling". Every code step carries the complete text to write.

**Type consistency.** `planH2`, `PLAN_MARK`, `sectionNodes`, `buildDag`, `normId`, `nodeName`, `planRegionHeadings`, `safeHref`, `decodeEntities`, `banner`, `decodeB64`, and `esc` are defined once and referenced consistently. Task 15 renames `planTasks` to `planRegionHeadings`; Step 3f retargets the one earlier assertion that names it, raises the guard floor to 20, and lists the three assertions in the same block that are expected to survive the rename untouched, so no task refers to the old name afterwards.

**Walk-tag coverage.** Twenty-three tasks, each tagged. Three are `browser-walk-only` (Tasks 13, 14, 23). Eleven walk cases, covering diagram legibility, index behavior, responsive layout, error isolation, print, inertness, graph correctness, the pending notice, cross-browser parity, HTML in a heading through the mermaid label path, and duplicate unnamespaced diagram ids across the two theme variants.

**Known risk carried forward.** Task 22 cannot pass from the working tree alone — it needs a real plugin install, and if the plugin payload does not ship `assets/`, Step 3 of that task is where it surfaces. That is deliberate: the spec names this the single highest-leverage failure point in the change.
