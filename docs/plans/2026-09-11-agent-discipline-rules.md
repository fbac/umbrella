# Agent Discipline Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use umbrella:subagent-driven-development (recommended) or umbrella:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. During per-task and final review, ALSO apply umbrella:review-lens (composed-surface-per-persona + walk-only flagging).

**Goal:** Add four discipline rules to umbrella's skills — minimum test subset, WHY-only comments, PR segmentation with a size budget, and a four-section PR body — landing each rule in the file the relevant agent actually reads.

**Architecture:** Every change is markdown text editing in `skills/` plus two constants in one shell test. Each rule has one *home* file that states it in full, and *reach points* in other files that restate the operative sentences rather than linking to them, because the two execution paths never load each other's files. Removing contradicting text is as important as adding new text.

**Tech Stack:** Markdown skill files, POSIX shell (`render_test.sh`), no build step, no package manager.

**Spec:** `docs/specs/2026-09-11-agent-discipline-rules-design.md`

---

## PR Segmentation

This plan declares **one segment**. Total estimate is roughly 390 lines added or
modified, under the 400-line soft threshold the plan itself introduces.

| Segment | Title | Branch | Base | Tasks | Est. lines added |
|---|---|---|---|---|---|
| 1 | Agent discipline rules | `feat/agent-discipline-rules` | `master` | 1-13 | ~390 |

The branch `feat/agent-discipline-rules` already exists and is checked out — it
is where the spec was committed. Per the rule this plan introduces, that
existing branch *is* segment 1's branch. No task creates a second branch.

**What the ~390 counts.** Changes under `skills/` and `assets/` only. The spec
and plan documents in `docs/` are excluded, as is `docs/briefs/`. Running Task
10's own backstop against `master` on this branch reports over 1,800 added lines
because it counts those two documents — that is the measurement working
correctly on a different question, not a contradiction. The budget governs code
and instruction text a reviewer must read, not the design artifacts that
describe them.

> [!NOTE]
> This table is block 28, the very block Task 1 adds to the catalog. It is
> included here deliberately: the first plan written under the new rule should
> obey it.

---

## Conventions for every task

**Working directory:** `/Users/fbac/projects/umbrella`

**Branch:** `feat/agent-discipline-rules` (already checked out — verify with
`git branch --show-current`, do not create a new one).

**Test command for the whole repository:**

```bash
bash assets/change-brief/tests/render_test.sh
```

Baseline before any change: `shell: 370 passed, 0 failed`. Task 1 raises the
count by one assertion; every later task must leave it green.

**This repository has no application code.** Tasks 1 and 2 touch a shell test
and are verified by running it. Tasks 3 through 11 edit instruction text whose
only mechanical check is that the suite stays green and the edited text reads as
intended; their behavioral verification is Task 12, which dispatches subagents
against scenarios that fail today. Do not invent unit tests for markdown files.

---

### Task 1: Catalog block 28 and unpin the test — `static-verifiable`

**Depends on:** none

**Files:**
- Modify: `assets/change-brief/BLOCKS.md:68-75`
- Modify: `assets/change-brief/tests/render_test.sh:1585`
- Modify: `assets/change-brief/tests/render_test.sh:1589`

Block 28 is a numbered addition to a catalog that `render_test.sh` pins by
count. The catalog row and the two test constants must change in the same
commit, or the suite goes red between commits.

- [ ] **Step 0: Get on the segment branch**

```bash
git checkout feat/agent-discipline-rules
git branch --show-current
```

Expected: `feat/agent-discipline-rules`. The branch already exists — do not use
`-b`. This is the step zero the rule in Task 7 requires of every segment's first
task; this plan obeys the rule it ships.

- [ ] **Step 1: Run the suite to record the baseline**

```bash
bash assets/change-brief/tests/render_test.sh 2>&1 | tail -1
```

Expected: `shell: 370 passed, 0 failed`

- [ ] **Step 2: Tighten the test to expect 28 blocks, and watch it fail**

In `assets/change-brief/tests/render_test.sh`, change line 1585 from:

```sh
for n in $(seq 1 27); do
```

to:

```sh
for n in $(seq 1 28); do
```

and change line 1589 from:

```sh
chk "27 catalog rows" "$(grep -cE '^\| [0-9]+ \|' "$B" 2>/dev/null || echo 0)" "27"
```

to:

```sh
chk "28 catalog rows" "$(grep -cE '^\| [0-9]+ \|' "$B" 2>/dev/null || echo 0)" "28"
```

- [ ] **Step 3: Run the suite to verify it fails for the right reason**

```bash
bash assets/change-brief/tests/render_test.sh 2>&1 | grep -E "FAIL|passed,"
```

Expected: two failures — `block 28 catalogued` reported missing, and
`28 catalog rows` reporting `27` where `28` was wanted. If you see any other
failure, stop: you changed the wrong line.

- [ ] **Step 4: Add block 28 to the catalog**

In `assets/change-brief/BLOCKS.md`, find the "Plan blocks — always present"
table, which currently reads:

```markdown
| # | Block |
|---|---|
| 24 | Tasks with steps and `- [ ]` checkboxes |
| 25 | Walk tag per task |
| 26 | `**Depends on:**` per task (`none` when independent) |
| 27 | Browser-Walk Inventory |
```

Add one row so it reads:

```markdown
| # | Block |
|---|---|
| 24 | Tasks with steps and `- [ ]` checkboxes |
| 25 | Walk tag per task |
| 26 | `**Depends on:**` per task (`none` when independent) |
| 27 | Browser-Walk Inventory |
| 28 | `## PR Segmentation` table — one row per pull request, always present even when there is only one |
```

- [ ] **Step 5: Run the suite to verify it passes**

```bash
bash assets/change-brief/tests/render_test.sh 2>&1 | tail -1
```

Expected: `shell: 371 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add assets/change-brief/BLOCKS.md assets/change-brief/tests/render_test.sh
git commit -m "feat(blocks): add block 28, the PR Segmentation table"
```

---

### Task 2: Widen the plan-block range from 24-27 to 24-28 — `static-verifiable`

**Depends on:** Task 1

**Files:**
- Modify: `skills/writing-plans/SKILL.md:23`
- Modify: `skills/writing-plans/plan-document-reviewer-prompt.md:34`
- Modify: `skills/writing-plans/plan-document-reviewer-prompt.md:38`
- Modify: `skills/brainstorming/spec-document-reviewer-prompt.md:44`

Four places bound the plan-block range. Leaving any at `24-27` tells an agent
that block 28 is not a plan block, which contradicts Task 1.

- [ ] **Step 1: Confirm exactly four occurrences exist**

```bash
grep -rn "24-27" skills/
```

Expected: exactly four lines — `writing-plans/SKILL.md:23`,
`plan-document-reviewer-prompt.md:34`, `plan-document-reviewer-prompt.md:38`,
`brainstorming/spec-document-reviewer-prompt.md:44`. If the count differs, stop
and report; the spec's blast-radius claim is wrong and the plan needs revising.

- [ ] **Step 2: Rewrite all four**

```bash
sed -i '' 's/plan blocks 24-27/plan blocks 24-28/g; s/Blocks 24-27/Blocks 24-28/g; s/\*\*plan blocks 24-27 only\*\*/**plan blocks 24-28 only**/g' \
  skills/writing-plans/SKILL.md \
  skills/writing-plans/plan-document-reviewer-prompt.md \
  skills/brainstorming/spec-document-reviewer-prompt.md
```

- [ ] **Step 3: Verify no occurrence survives**

```bash
grep -rn "24-27" skills/ ; echo "exit=$?"
```

Expected: no output, `exit=1`. An `exit=0` with output means a phrasing the
`sed` did not match — fix it by hand.

- [ ] **Step 4: Verify the suite is still green**

```bash
bash assets/change-brief/tests/render_test.sh 2>&1 | tail -1
```

Expected: `shell: 371 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add skills/
git commit -m "chore(skills): widen plan-block range to 24-28"
```

---

### Task 3: Retarget TDD at behaviors — `static-verifiable`

**Depends on:** none

**Files:**
- Modify: `skills/test-driven-development/SKILL.md:331` (checklist line)
- Modify: `skills/test-driven-development/SKILL.md:338` (checklist line)
- Modify: `skills/test-driven-development/SKILL.md` (new section before `## The Iron Law`)

This is the home of R1. The two checklist lines are the specific text that
produces test bloat today, so they must be rewritten, not merely supplemented.

- [ ] **Step 1: Add the minimum-subset section**

In `skills/test-driven-development/SKILL.md`, immediately before the line
`## The Iron Law`, insert:

```markdown
## The Minimum Subset

**The unit of testing is the behavior in the contract, not the function.** A
contract is what the feature promises, what the bug report says is broken, or
what the issue asks for.

Write one test per behavior in that contract, plus one test per corner case a
real caller can produce in production. Nothing else.

**The reachability test.** A corner case earns a test only if you can name the
caller and the input that reaches it. If you cannot, it is unreachable: the test
asserts something no user will ever observe, while still breaking every time the
code is refactored. Delete it.

**Trivial-code exemption.** Production code may ship with no test when it is a
pure passthrough, a constant or configuration declaration, or an accessor with
no branching and no computation. This needs no partner permission. Everything
else still needs a failing test first.

**Anti-goals.** These are not goals and never were:

- No coverage percentage is a target. Not 100%, not 80%.
- A test per function is not a requirement.
- A test that exists only to raise a number gets deleted, not kept.

More tests is not better. A suite that is expensive to run and expensive to
change, whose failures carry no signal about whether the feature works, is worse
than a small suite that fails only when something real broke.
```

- [ ] **Step 2: Retarget the Iron Law at behaviors**

Find:

````markdown
```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```
````

Replace with:

````markdown
```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Read "production code" as **a behavior in the contract**, not "a function". A
function that carries no contract behavior — see the trivial-code exemption
above — is outside the Law, not an exception to it.
````

- [ ] **Step 3: Rewrite the two checklist lines**

In the `## Verification Checklist` section, change:

```markdown
- [ ] Every new function/method has a test
```

to:

```markdown
- [ ] Every behavior in the contract has a test
```

and change:

```markdown
- [ ] Edge cases and errors covered
```

to:

```markdown
- [ ] Production-reachable corner cases covered; unreachable ones deliberately not written
- [ ] No test exists only to raise coverage
```

- [ ] **Step 4: Add the new rationalizations to the existing table**

In the `## Common Rationalizations` table, add three rows at the end:

```markdown
| "More coverage is safer" | Unreachable-input tests break on refactors and catch nothing. Cost without benefit. |
| "I'll test every method to be thorough" | Thorough means every contract behavior, not every method. |
| "This getter could break someday" | Name the caller and the input. Can't? Don't write it. |
```

- [ ] **Step 5: Verify the contradicting text is gone**

```bash
grep -n "Every new function/method has a test\|Edge cases and errors covered" skills/test-driven-development/SKILL.md; echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add skills/test-driven-development/SKILL.md
git commit -m "feat(tdd): retarget the Iron Law at behaviors, add minimum subset"
```

---

### Task 4: Comment rule and test rule for implementer subagents — `static-verifiable`

**Depends on:** Task 3

**Files:**
- Modify: `skills/subagent-driven-development/implementer-prompt.md` (new section after `## Code Organization`)
- Modify: `skills/subagent-driven-development/implementer-prompt.md:96` (self-review line)

This is the home of R2. Note the whole file is one fenced prompt template — keep
the four-space indentation of the surrounding lines or the template breaks.

- [ ] **Step 1: Add the comment rule**

In `skills/subagent-driven-development/implementer-prompt.md`, immediately after
the `## Code Organization` block and before `## When You're in Over Your Head`,
insert (preserving the four-space indent):

```
    ## Comments

    Code says what it does. Comments say **why** it does it that way. A comment
    that paraphrases the code beneath it is forbidden — it goes stale on the
    first edit, and a stale comment is worse than none because a reader trusts
    it and is wrong.

    Write a comment when a reader who knows the language would still ask *why
    like this?*:
    - a non-obvious constraint
    - a workaround for external behavior (link the issue)
    - an alternative you deliberately rejected, and why
    - an ordering requirement that looks arbitrary
    - a business rule not derivable from the code

    Never write: narration of the next line, section-divider banners, changelog
    comments, or commented-out code.

    **Exempt:** public API docstrings. They are contracts for callers who will
    never read the body, not narration of it.

    **Scope:** new code you write, plus any comment sitting on a line you are
    already editing — rewrite it to a why, or delete it. Do not sweep the
    repository for comments to fix; that is not your task.
```

- [ ] **Step 2: Replace the comprehensiveness self-review line**

In the `**Testing:**` block of `## Before Reporting Back: Self-Review`, change:

```
    - Are tests comprehensive?
```

to:

```
    - Does every behavior in the contract have a test?
    - Did I write any test for an input no real caller can produce? Delete it.
    - Did I test a trivial passthrough, constant, or branchless accessor? Delete it.
```

- [ ] **Step 3: Verify the replaced line is gone and indentation held**

```bash
grep -n "Are tests comprehensive?" skills/subagent-driven-development/implementer-prompt.md; echo "exit=$?"
grep -c "^    " skills/subagent-driven-development/implementer-prompt.md
```

Expected: first command prints nothing with `exit=1`. Second prints a count
greater than 90 — the file has 77 indented lines before this task and roughly 98
after, so anything in the 90s confirms the indented template body is intact.

- [ ] **Step 4: Verify the edge-case-handling line was NOT touched**

```bash
grep -c "Are there edge cases I didn't handle?" skills/subagent-driven-development/implementer-prompt.md
```

Expected: `1`. Do not check its line number — Step 1 inserts about 24 lines
above it, so it moves. This line is about *code handling* an edge case,
not about writing a test for it. R1 constrains only the second. Deleting it is a
plan violation.

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/implementer-prompt.md
git commit -m "feat(implementer): add WHY-only comment rule, retarget test self-review"
```

---

### Task 5: Reach the inline execution path — `static-verifiable`

**Depends on:** Task 4

**Files:**
- Modify: `skills/executing-plans/SKILL.md` (new section after `### Step 2: Execute Tasks`)

`executing-plans` reads no prompt templates, so it never sees
`implementer-prompt.md`. The rules are **restated** here, not linked, because an
agent acts on what is in its context window.

- [ ] **Step 1: Add the discipline section**

In `skills/executing-plans/SKILL.md`, immediately after the `### Step 2: Execute
Tasks` block and before `### Step 3: Complete Development`, insert:

```markdown
### Step 2b: Discipline Rules While You Work

You are the coding agent here. These rules apply to you exactly as they apply to
an implementer subagent.

**Tests — minimum subset.** The unit of testing is the behavior in the contract,
not the function. Write one test per behavior the plan's task describes, plus
one per corner case a real caller can produce in production. If you cannot name
the caller and the input that reaches a corner case, do not write the test. Pure
passthroughs, constants, configuration, and branchless accessors need no test at
all. No coverage percentage is a target. See umbrella:test-driven-development
for the full rule.

**Comments — why, not what.** Code says what it does; comments say why it does
it that way. A comment that paraphrases the line beneath it is forbidden. Write
one for a non-obvious constraint, an external workaround, a rejected
alternative, a surprising ordering requirement, or a business rule the code
cannot show. Public API docstrings are exempt. The rule covers new code plus
comments on lines you are already editing — do not sweep the repository.

**Segment branches.** A plan may contain a `## PR Segmentation` table and a step
zero on a task that checks out a branch. Run those steps exactly as written. Do
not create a branch the plan did not name, and do not skip a checkout because
you are "already on a branch".
```

- [ ] **Step 2: Verify the section landed between the right neighbors**

```bash
grep -n "^### Step 2b\|^### Step 3" skills/executing-plans/SKILL.md
```

Expected: `Step 2b` on a lower line number than `Step 3`.

- [ ] **Step 3: Verify both rules are restated, not linked**

```bash
grep -o "minimum subset\|paraphrases the line" skills/executing-plans/SKILL.md | wc -l
```

Expected: `2`. A count of `0` means you wrote a pointer instead of the rule.
Uses `grep -o | wc -l` rather than `grep -c` because `grep -c` counts matching
*lines*, so re-wrapping the inserted text would change the answer.

- [ ] **Step 4: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "feat(executing-plans): restate test and comment rules for the inline path"
```

---

### Task 6: Remove the contradicting review text — `static-verifiable`

**Depends on:** Task 3

**Files:**
- Modify: `skills/requesting-code-review/code-reviewer.md:55`
- Modify: `skills/requesting-code-review/code-reviewer.md:137`
- Modify: `skills/requesting-code-review/code-reviewer.md` (Testing block)

This file is read by both the per-task code quality reviewer and the final
branch reviewer. Its worked example currently teaches the opposite of R1 by
demonstration, which outweighs a rule stated elsewhere.

- [ ] **Step 1: Rewrite the Testing checklist**

Find this block (around line 53):

```markdown
    **Testing:**
    - Tests verify real behavior, not mocks?
    - Edge cases covered?
    - Integration tests where they matter?
    - All tests passing?
```

Replace with:

```markdown
    **Testing:**
    - Tests verify real behavior, not mocks?
    - Does each test map to a behavior in the contract, or to a corner case a
      real caller can produce? Flag tests that map to neither.
    - Any test for a trivial passthrough, constant, or branchless accessor?
      That is bloat — flag it for deletion.
    - Integration tests where they matter?
    - All tests passing?

    **Comments:**
    - Does every comment explain *why*, not restate *what* the code does?
      Flag any comment that paraphrases the line beneath it.
    - Public API docstrings are exempt — do not flag those.
```

- [ ] **Step 2: Rewrite the worked example's coverage praise**

Find (around line 137):

```markdown
- Comprehensive test coverage (18 tests, all edge cases)
```

Replace with:

```markdown
- Tests map cleanly to the four documented behaviors, with no filler (search.test.ts)
```

- [ ] **Step 3: Verify both contradictions are gone**

```bash
grep -n "Edge cases covered?\|Comprehensive test coverage" skills/requesting-code-review/code-reviewer.md; echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 4: Verify the code-handling check survived**

```bash
grep -n "Edge cases handled?" skills/requesting-code-review/code-reviewer.md
```

Expected: one match at line 45, under `**Code quality:**`. This asks whether the
*code* handles edge cases, which R1 does not constrain. Deleting it is a plan
violation.

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/code-reviewer.md
git commit -m "fix(code-review): stop teaching coverage bloat, add comment check"
```

---

### Task 7: PR segmentation in writing-plans — `static-verifiable`

**Depends on:** Task 1

**Files:**
- Modify: `skills/writing-plans/SKILL.md` (new section after `## Bite-Sized Task Granularity`)

This is the home of R3.

- [ ] **Step 1: Add the segmentation section**

In `skills/writing-plans/SKILL.md`, immediately after the `## Bite-Sized Task
Granularity` section and before `## Walk-Tagging (Umbrella)`, insert:

```markdown
## PR Segmentation (Umbrella)

**Why this exists:** nobody reviews 5,000 lines. Neither a human nor an agent
holds that much in working memory, so review degrades to a rubber stamp exactly
when the change is largest. Plan time is the only moment when splitting is free:
once code exists on one branch, splitting means rewriting history across mixed
commits.

**The budget.** Count lines **added or modified** — the added column of
`git diff --numstat`, not added minus deleted. A pure-deletion change is easy to
review and must not be penalized; a rewrite that nets zero is not easy to review
and must not be waved through. Count production and test code together. Exclude
generated files, lockfiles, vendored dependencies, and `docs/briefs/`.

| Estimate | Rule |
|---|---|
| Under 400 | Single segment. |
| 400 to 800 | State in one sentence why it stays single, or segment it. |
| Over 800 | MUST segment. This is blocking, not advisory. |

**Block 28 — the table.** Every plan carries a `## PR Segmentation` section,
whether it declares one segment or six:

| Segment | Title | Branch | Base | Tasks | Est. lines added |
|---|---|---|---|---|---|
| 1 | Parser | `feat/x-parser` | `master` | 1-4 | 320 |
| 2 | Wiring | `feat/x-wiring` | `feat/x-parser` | 5-7 | 280 |

Label the estimate column with the budget metric. Never write "net".

**Where segment 1's branch comes from.** Segment N bases on segment N-1's
branch. Segment 1 depends on the workspace state `umbrella:using-git-worktrees`
left behind:

| Workspace state | Segment 1's branch | Step zero |
|---|---|---|
| On a branch (worktree or not) | That existing branch | `git checkout <branch>` |
| Normal checkout, no feature branch | A new branch off the base | `git checkout -b <branch> <base>` |
| Detached HEAD, externally managed | A new branch off the current commit | `git checkout -b <branch>` |

**Never create a second branch beside an existing worktree branch.** That
orphans the branch the worktree exists for.

**Step zero.** Each segment's first task carries a step zero that puts the agent
on the segment branch, using the command from the table above. Because the step
lives in the plan, both execution paths get it without either needing to
understand segmentation as a concept.

**Each segment ships on its own.** At the end of a segment the repository is
green and nothing is half-wired. If a boundary would leave broken state, the
boundary is in the wrong place — move it, do not ship it.
```

- [ ] **Step 2: Add the comment constraint to the authoring rules**

In the `## No Placeholders` section, after the existing bullet list, add:

```markdown
**Code shown in plan steps carries no what-comments.** Implementers copy your
code blocks verbatim, so a comment that paraphrases the line beneath it
propagates into the codebase. Comments in plan code explain why, or they are
absent. See umbrella:subagent-driven-development's implementer prompt for the
full rule.
```

- [ ] **Step 3: Add block 28 to the Self-Review checklist**

In the `## Self-Review` section, after item **5. Dependency declarations
(Umbrella)**, add:

```markdown
**6. PR segmentation (Umbrella):** Is there a `## PR Segmentation` section? Does
the total estimate respect the budget — segmented if over 800, justified if
between 400 and 800? Does every segment after the first base on its predecessor?
Does each segment's first task carry a step zero?
```

- [ ] **Step 4: Verify the section landed and the metric is right**

```bash
grep -n "^## PR Segmentation (Umbrella)" skills/writing-plans/SKILL.md
grep -c "net LoC\|estimated net" skills/writing-plans/SKILL.md
```

Expected: one match for the heading; `0` for the second — the word "net" must
not describe the estimate.

- [ ] **Step 5: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat(writing-plans): add PR segmentation budget and block 28"
```

---

### Task 8: Make the plan gate enforce segmentation — `static-verifiable`

**Depends on:** Task 2, Task 7

**Files:**
- Modify: `skills/writing-plans/plan-document-reviewer-prompt.md` (block coverage list)

The `>90` gate at `skills/writing-plans/SKILL.md:169` is the only thing between a
plan and execution. A finding that does not push the score under the gate leaves
the hard threshold soft in practice.

- [ ] **Step 1: Add block 28 to the graded list**

In `skills/writing-plans/plan-document-reviewer-prompt.md`, find the
`## Plan Block Coverage` list ending with the block 27 bullet, and add after it
(preserving the four-space indent):

```
    - **28** — a `## PR Segmentation` section exists with at least one row
      carrying segment number, title, branch, base, task range, and an estimate
      labelled as lines added. Check the base chain: segment N must base on
      segment N-1's branch. Check that each segment's first task carries a step
      zero putting the agent on that branch.

    **Segmentation is a blocking finding.** If the plan's total estimate exceeds
    800 lines added while declaring a single segment, report status
    `Issues Found` with a score **not above 90**. Do not soften this to a
    recommendation: the gate is `>90`, so an advisory note would let the plan
    through and make the hard threshold meaningless. A plan between 400 and 800
    lines with a single segment and no stated justification is the same finding.
```

- [ ] **Step 2: Verify block 28 is graded and the range was widened**

```bash
grep -n "28" skills/writing-plans/plan-document-reviewer-prompt.md | head -5
grep -c "24-27" skills/writing-plans/plan-document-reviewer-prompt.md
```

Expected: matches showing `24-28` and the new block 28 bullet; `0` for the
second command.

- [ ] **Step 3: Commit**

```bash
git add skills/writing-plans/plan-document-reviewer-prompt.md
git commit -m "feat(plan-review): grade block 28, make oversized plans blocking"
```

---

### Task 9: Replace the PR body template — `static-verifiable`

**Depends on:** none

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md:122-137` (Option 2 body)

This is the home of R4.

- [ ] **Step 1: Replace the Option 2 block**

In `skills/finishing-a-development-branch/SKILL.md`, find the
`#### Option 2: Push and Create PR` block, which currently reads:

````markdown
```bash
# Push branch
git push -u origin <feature-branch>

# Create PR
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<2-3 bullets of what changed>

## Test Plan
- [ ] <verification steps>
EOF
)"
```
````

Replace it with:

````markdown
```bash
# Push branch
git push -u origin <feature-branch>

# Create PR
gh pr create --title "<title>" --body "$(cat <<'EOF'
## TL;DR
<One or two sentences: what this PR does.>

## Why
<What is broken, missing, or painful today, and what it costs to leave it.>

## What
<What was done about it. Bullets at file or component granularity.>

## Follow-ups
<Actions the reader must take outside this PR, e.g. "create SENTRY_DSN in staging".>
EOF
)"
```

**Write it in simplified technical English, and respect the budgets** — they are
what keep a PR body from becoming the wall of text nobody reads:

| Section | Budget | Contains |
|---|---|---|
| TL;DR | at most 2 sentences | What this PR does. |
| Why | at most 4 sentences or bullets | What is broken today. The reader is deciding whether to merge; this is the section that decides it. |
| What | at most 8 bullets | What you did about it. |
| Follow-ups | optional | Actions outside this PR. **Omit the whole section when empty** — never write "None". |

There is no Test Plan section. Verification is already gated by
`umbrella:verification-before-completion` before you reach this step, and a
checklist of steps you already ran is exactly the padding these budgets exist to
remove.
````

- [ ] **Step 2: Verify Test Plan is gone and the four sections are present**

```bash
grep -n "## Test Plan" skills/finishing-a-development-branch/SKILL.md; echo "exit=$?"
grep -c "## TL;DR\|## Why\|## What\|## Follow-ups" skills/finishing-a-development-branch/SKILL.md
```

Expected: first prints nothing with `exit=1`; second prints `4`.

- [ ] **Step 3: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "feat(finishing): replace PR body with TL;DR/Why/What/Follow-ups"
```

---

### Task 10: Stacked pull requests and the size backstop — `static-verifiable`

**Depends on:** Task 9

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md` (new Step 1b after Step 1)
- Modify: `skills/finishing-a-development-branch/SKILL.md` (new section after Option 4)

- [ ] **Step 1: Add the size backstop as a new step**

Immediately after the `### Step 1: Verify Tests` section and before
`### Step 2: Detect Environment`, insert:

````markdown
### Step 1b: Measure the Diff

```bash
BASE=$(git merge-base HEAD master 2>/dev/null || git merge-base HEAD main)
git diff --numstat "$BASE"..HEAD \
  | grep -vE '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|Cargo\.lock|^docs/briefs/|/vendor/)' \
  | awk '{ added += $1 } END { print added+0 }'
```

That number is lines added or modified, with generated files, lockfiles,
vendored dependencies and `docs/briefs/` excluded.

**If it exceeds 800 and this is single-segment work, stop and report before
opening anything:**

```
This branch adds <N> lines, past the 800-line review budget. Nobody reviews a
diff this size carefully — review degrades to a rubber stamp.

Options:
1. Open it as one PR anyway (you accept the review cost)
2. Split it into a stack before opening (I'll propose boundaries)

Which?
```

Work with **no plan at all** — a branch you finished by hand — counts as
single-segment, so this check still applies. Only *stacking* is opt-in; the
size warning never is.

Do not rewrite history on your own to split the branch. Propose boundaries and
let your partner choose.
````

- [ ] **Step 2: Add the stacked-PR section**

Immediately after the `#### Option 4: Discard` block and before
`### Step 6: Cleanup Workspace`, insert:

````markdown
### Stacked Pull Requests

**How you know.** Read the plan's `## PR Segmentation` table. A table with two or
more rows means a stack. **No plan, or a single row, means the skill behaves
exactly as it always has — one branch, one pull request.** Stacking is opt-in;
the Step 1b size check is not.

**When.** Open all pull requests in one pass, at the end, after the full test
suite passes on the tip segment. Opening a segment's PR as soon as its tasks
finish puts a reviewer in front of code that later segments can still change.

**Order.** Push and open strictly in segment order, 1 to M. Creating segment N's
pull request before segment N-1's branch exists on the remote fails, so order is
correctness, not preference.

```bash
# For each segment in order 1..M:
git push -u origin <segment-branch>
gh pr create \
  --base <previous-segment-branch> \
  --title "[N/M] <segment title>" \
  --body "$(cat <<'EOF'
## TL;DR
<What this segment does.>

**Stack:** 1. <seg-1 title> · 2. <seg-2 title> · 3. <seg-3 title>  ← you are here: N

## Why
<What is broken today that the whole stack addresses, and what this segment contributes.>

## What
<What this segment changed.>
EOF
)"
```

Segment 1 uses the repository base branch for `--base`.

**When something fails mid-stack:**

| Failure | What to do |
|---|---|
| `git push` fails on segment K | Stop. Do not attempt K+1 — its base does not exist on the remote, so it cannot succeed. Report which segments landed and the command to resume at K. |
| `gh pr create` fails on segment K | Stop for the same reason: K+1's `--base` would point at a branch with no PR and the stack reads out of order. Report and give the resume command. |
| A segment branch named in the table does not exist | Report the mismatch and push nothing. Execution diverged from the plan, and guessing which branch was meant is worse than asking. |

**Never roll back automatically.** Report partial progress; do not delete remote
branches or close pull requests to "clean up".

**Options 1, 3 and 4 act on the whole stack:**

| Option | Stack behavior |
|---|---|
| 1. Merge locally | Merge segments in order 1 to M, running tests after each. Stop at the first failure and report which segment broke, leaving 1..K-1 merged. |
| 2. Create PR | The loop above. Worktree preserved. |
| 3. Keep as-is | Report **every** segment branch by name, so none is forgotten. |
| 4. Discard | The typed confirmation lists **all** segment branches; delete them in reverse order, M to 1. |
````

- [ ] **Step 3: Verify both sections landed in the right order**

```bash
grep -n "^### Step 1b: Measure the Diff\|^### Step 2: Detect Environment\|^### Stacked Pull Requests\|^### Step 6: Cleanup" skills/finishing-a-development-branch/SKILL.md
```

Expected: line numbers strictly increasing in that order.

- [ ] **Step 4: Verify the measurement command actually runs**

```bash
BASE=$(git merge-base HEAD master); git diff --numstat "$BASE"..HEAD | grep -vE '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|Cargo\.lock|^docs/briefs/|/vendor/)' | awk '{ added += $1 } END { print added+0 }'
```

Expected: a plain integer. If it errors, the command in the skill is broken and
must be fixed now — an agent will copy it verbatim.

- [ ] **Step 5: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "feat(finishing): add size backstop and stacked-PR handling"
```

---

### Task 11: Reconcile the summary tables with the stack rules — `static-verifiable`

**Depends on:** Task 10

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md` (Quick Reference table)
- Modify: `skills/finishing-a-development-branch/SKILL.md` (Common Mistakes)
- Modify: `skills/finishing-a-development-branch/SKILL.md` (Red Flags)

Three sections restate per-option behavior. Left alone they contradict Task 10 —
the exact failure this whole change exists to prevent.

- [ ] **Step 1: Extend the Quick Reference table**

Find:

```markdown
| Option | Merge | Push | Keep Worktree | Cleanup Branch |
|--------|-------|------|---------------|----------------|
| 1. Merge locally | yes | - | - | yes |
| 2. Create PR | - | yes | yes | - |
| 3. Keep as-is | - | - | yes | - |
| 4. Discard | - | - | - | yes (force) |
```

Replace with:

```markdown
| Option | Merge | Push | Keep Worktree | Cleanup Branch | With a stack |
|--------|-------|------|---------------|----------------|--------------|
| 1. Merge locally | yes | - | - | yes | Merge 1→M, test after each, stop at first failure |
| 2. Create PR | - | yes | yes | - | Push and open 1→M, `--base` chained |
| 3. Keep as-is | - | - | yes | - | Report every segment branch by name |
| 4. Discard | - | - | - | yes (force) | Confirm all branches, delete M→1 |
```

- [ ] **Step 2: Add two Common Mistakes**

At the end of the `## Common Mistakes` section, add:

```markdown
**Opening stacked PRs out of order**
- **Problem:** segment N's `--base` points at a branch not yet on the remote, so `gh pr create` fails or the stack reads wrong
- **Fix:** push and open strictly 1 to M; stop at the first failure

**Opening a PR without measuring the diff**
- **Problem:** a 3,000-line PR gets a rubber-stamp review
- **Fix:** run Step 1b first; over 800 lines, report and offer to split
```

- [ ] **Step 3: Add three Red Flags**

In the `## Red Flags` section, add to the **Never** list:

```markdown
- Open a pull request without running the Step 1b size check
- Open stacked pull requests out of segment order
- Delete remote branches or close PRs to "clean up" a partially-created stack
```

and to the **Always** list:

```markdown
- Measure the diff before offering options
- Report partial stack progress rather than rolling it back
```

- [ ] **Step 4: Verify no stale single-PR claim survives**

```bash
grep -n "## Test Plan" skills/finishing-a-development-branch/SKILL.md; echo "exit=$?"
grep -c "There is no Test Plan section" skills/finishing-a-development-branch/SKILL.md
```

Expected: first prints nothing with `exit=1` — no Test Plan *heading* survives.
Second prints `1`: Task 9 deliberately added the prose sentence explaining the
removal, so grepping for the bare words "Test Plan" would match it and look like
a failure. Grep for the heading, not the phrase.

`exactly 4 options` may still appear elsewhere in the file — the option *count*
is unchanged by this work, only what each option does with a stack. Leave it.

- [ ] **Step 5: Run the full suite**

```bash
bash assets/change-brief/tests/render_test.sh 2>&1 | tail -1
```

Expected: `shell: 371 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "fix(finishing): reconcile summary tables with stack behavior"
```

---

### Task 12: Behavioral verification by subagent — `static-verifiable`

**Depends on:** Task 5, Task 6, Task 8, Task 11

**Files:**
- Create: none. This task dispatches subagents and records results.

Five scenarios, each one that **fails against the pre-change skill text**. That
is what makes each worth running, and it is why there are five rather than a
matrix of every skill against every rule. Follow
`skills/writing-skills/testing-skills-with-subagents.md`.

Each subagent must be dispatched **fresh**, with no memory of this plan, and
must be given only the skill text plus the scenario.

- [ ] **Step 1: Scenario A — minimum test subset**

Dispatch a subagent with `skills/test-driven-development/SKILL.md` and this task:

```
Here is a module with one bug and four trivial accessors:

class Cart:
    def __init__(self): self._items = []
    @property
    def items(self): return self._items
    @property
    def count(self): return len(self._items)
    @property
    def is_empty(self): return len(self._items) == 0
    @property
    def currency(self): return "USD"
    def total(self):
        return sum(i.price * i.qty for i in self._items)

Bug: total() ignores per-item discounts. Item has a .discount float 0.0-1.0.
Fix it, following the skill.
```

PASS: exactly one new test, covering discounted totalling. Possibly a second for
a production-reachable corner case (discount 0.0 or 1.0) with the caller named.
FAIL: a test for `items`, `count`, `is_empty`, or `currency`; any test for a
discount outside 0.0-1.0 without naming how a caller produces it; any mention of
a coverage target.

- [ ] **Step 2: Scenario B — comments**

Dispatch a subagent with `skills/subagent-driven-development/implementer-prompt.md`
and this task:

```
Write a function `retry_with_backoff(fn, attempts=3)` in Python that retries a
callable with exponential backoff, sleeping 2**n seconds between attempts.
The remote API rate-limits at 10 req/s, which is why the first sleep is 1s
rather than 0s.
```

PASS: no comment paraphrases the line beneath it. If a comment exists, it
explains the rate-limit reason for the first sleep.
FAIL: comments like `# loop over attempts`, `# sleep`, `# return the result`, or
a banner such as `# ---- helpers ----`.

- [ ] **Step 3: Scenario C — segmentation**

Dispatch a subagent with `skills/writing-plans/SKILL.md` and a spec describing a
change of roughly 1,500 lines across three subsystems (a parser, a storage
layer, and an HTTP API). Ask it to write the plan.

PASS: a `## PR Segmentation` table with two or more rows; segment 2 based on
segment 1's branch; a step zero on each segment's first task.
FAIL: one segment for 1,500 lines; a missing table; a base chain where every
segment bases on `master`.

- [ ] **Step 4: Scenario D — PR body, single**

Dispatch a subagent with `skills/finishing-a-development-branch/SKILL.md` on a
finished single-segment branch and choose Option 2.

PASS: body has exactly TL;DR, Why, What, and Follow-ups only if non-empty; each
within budget; no Test Plan.
FAIL: a Test Plan section; a `Follow-ups` section reading "None"; a What section
past 8 bullets.

- [ ] **Step 5: Scenario E — PR body, stacked**

Dispatch a subagent with `skills/finishing-a-development-branch/SKILL.md` and a
plan whose `## PR Segmentation` table has two rows, then choose Option 2.

PASS: two pull requests, opened in segment order; segment 2's `--base` is
segment 1's branch; `[1/2]` and `[2/2]` title prefixes; a stack map on both.
FAIL: one combined PR; both based on `master`; PRs opened in reverse order.
This scenario exists separately from Step 4 because a single-branch run cannot
exercise the `--base` chain at all.

- [ ] **Step 6: Record results and fix any failure**

Write PASS/FAIL per scenario into the commit message. Any FAIL means the skill
text did not land the rule — fix the text and re-run that scenario. Do not
proceed with a failing scenario recorded as "close enough".

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test(skills): behavioral verification of the four discipline rules"
```

If all five scenarios passed and no skill text needed fixing, there is nothing
to commit — skip this step rather than creating an empty commit. Record the
five results in your report instead.

---

### Task 13: Confirm the brief renders the new block — `browser-walk-only`

**Depends on:** Task 12

**Files:**
- Modify: none. This task renders and inspects.

Spec requirement 28. A `## PR Segmentation` table has never been rendered in a
brief before, and the PR-body template embeds `## TL;DR` and `## Why` inside a
fence — those must render as code, not as sections in the index.

- [ ] **Step 1: Render the brief with both sources**

```bash
assets/change-brief/render.sh \
  docs/specs/2026-09-11-agent-discipline-rules-design.md \
  docs/plans/2026-09-11-agent-discipline-rules.md \
  -o docs/briefs/2026-09-11-agent-discipline-rules.html
```

Expected: exit 0, and the output path printed.

- [ ] **Step 2: Confirm the payload is non-empty before opening**

```bash
python3 -c "
import re,base64
s=open('docs/briefs/2026-09-11-agent-discipline-rules.html').read()
b=re.search(r'data-brief=\"([^\"]*)\"',s).group(1)
d=base64.b64decode(re.sub(r'\s','',b)).decode('utf8')
print('chars:',len(d))
print('PR Segmentation:',d.count('PR Segmentation'))
print('tasks:',len(re.findall(r'^### Task ',d,re.M)))
"
```

Expected: chars over 30000, `PR Segmentation` at least 5, tasks 13.

Note: `data-brief` is line-wrapped base64. A regex of `[A-Za-z0-9+/=]+` will
match zero characters and look like an empty payload — use `[^"]*` as above.

- [ ] **Step 3: Execute the browser walk**

Run walk case 1 in `## Browser-Walk Inventory` below and record pass or fail.

- [ ] **Step 4: Commit any fix the walk required**

```bash
git add -A
git commit -m "fix(brief): corrections from the browser walk"
```

If the walk passed with no changes, skip this step — do not create an empty
commit.

---

## Browser-Walk Inventory

1. **The PR Segmentation table and the fenced PR-body headings.** Render the
   brief with the command in Task 13, Step 1, then open
   `docs/briefs/2026-09-11-agent-discipline-rules.html` in a desktop browser at
   a normal window width of about 1400 pixels. No account and no login is
   involved; the file opens directly from disk. First, look at the index in the
   left sidebar and read its entries top to bottom. Confirm that `TL;DR`, `Why`,
   `What`, and `Follow-ups` do **not** appear there as sections — those four
   headings live inside a fenced code block showing the pull request body
   template, so they must render as code, not as document structure. Seeing them
   in the index means the renderer is treating fenced content as headings, which
   is a renderer escaping bug to report rather than a plan change. Second, click
   the `PR Segmentation` entry in the index and confirm the page scrolls to the
   section and that its table is fully legible, with the estimate column headed
   "Est. lines added". Third, narrow the browser window to roughly 500 pixels
   wide and confirm the table scrolls horizontally inside its own container
   rather than forcing the whole page to scroll sideways. Fourth, switch your
   operating system between light and dark appearance and confirm the table
   text, the table borders, and the two mermaid diagrams all remain readable in
   both, with no white-on-white or black-on-black text. Record pass or fail for
   each of the four checks.
