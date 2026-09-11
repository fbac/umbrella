---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup
---

# Finishing a Development Branch

## Overview

Guide completion of development work by presenting clear options and handling chosen workflow.

**Core principle:** Verify tests → Detect environment → Present options → Execute choice → Clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## The Process

### Step 1: Verify Tests

**Before presenting options, verify tests pass:**

```bash
# Run project's test suite
npm test / cargo test / pytest / go test ./...
```

**If tests fail:**
```
Tests failing (<N> failures). Must fix before completing:

[Show failures]

Cannot proceed with merge/PR until tests pass.
```

Stop. Don't proceed to Step 2.

**If tests pass:** Continue to Step 2.

### Step 1b: Measure the Diff

```bash
BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null)
git diff --numstat "$BASE"..HEAD \
  | grep -vE '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|Cargo\.lock|^docs/briefs/|/vendor/)' \
  | awk '{ added += $1 } END { print added+0 }'
```

That number is lines added or modified, with generated files, lockfiles,
vendored dependencies and `docs/briefs/` excluded.

**Read it as an upper bound, then adjust.** The grep cannot know what kind of
repository this is, and the plan-time budget in `umbrella:writing-plans`
excludes documentation — READMEs, guides, and the spec and plan documents —
*unless* prose is the deliverable, as in a skills repository or a docs site. No
single pattern gets both cases right, so the judgement stays here: if a large
share of this number is documentation and documentation is not what this
repository ships, subtract it before comparing against the budget, and say so
when you report. A warning that is obviously about README churn teaches the
reader to ignore the next one.

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

**Where each answer leads.** This menu is not the option menu — Step 4's four
options still follow.

- **Chose 1 (one PR anyway):** continue to Step 2. Say nothing further about
  size; they decided.
- **Chose 2 (split):** propose boundaries as a list of segments, each with the
  commits or files it would carry and why it is independently shippable. Splitting
  an existing branch means rewriting history, so stop there and hand the proposal
  over — do not start rebasing. When they have split it, resume at Step 1b to
  re-measure.

### Step 2: Detect Environment

**Determine workspace state before presenting options:**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
```

This determines which menu to show and how cleanup works:

| State | Menu | Cleanup |
|-------|------|---------|
| `GIT_DIR == GIT_COMMON` (normal repo) | Standard 4 options | No worktree to clean up |
| `GIT_DIR != GIT_COMMON`, named branch | Standard 4 options | Provenance-based (see Step 6) |
| `GIT_DIR != GIT_COMMON`, detached HEAD | Reduced 3 options (no merge) | No cleanup (externally managed) |

### Step 3: Determine Base Branch

```bash
# Try common base branches
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

**Reuse `BASE` from Step 1b** — it is the same value, computed by the same
command in the same branch order. Do not recompute it a second way. If you ask
your partner instead ("This branch split from main - is that correct?") and they
name a different branch, the Step 1b measurement was against the wrong base:
re-run it before relying on the number.

### Step 4: Present Options

**Normal repo and named-branch worktree — present exactly these 4 options:**

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
4. Discard this work

Which option?
```

**Detached HEAD — present exactly these 3 options:**

```
Implementation complete. You're on a detached HEAD (externally managed workspace).

1. Push as new branch and create a Pull Request
2. Keep as-is (I'll handle it later)
3. Discard this work

Which option?
```

**Don't add explanation** - keep options concise.

### Step 5: Execute Choice

#### Option 1: Merge Locally

```bash
# Get main repo root for CWD safety
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# Merge first — verify success before removing anything
git checkout <base-branch>
git pull
git merge <feature-branch>

# Verify tests on merged result
<test command>

# Only after merge succeeds: cleanup worktree (Step 6), then delete branch
```

Then: Cleanup worktree (Step 6), then delete branch:

```bash
git branch -d <feature-branch>
```

#### Option 2: Push and Create PR

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
<Actions the reader must take outside this PR, e.g. "create SENTRY_DSN in staging". If there are none, delete this section and its heading — do not write "None".>
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

This is a deliberate trade, not a free win. A Test Plan served a second reader:
it showed a *reviewer* how the work was checked, not just that it was. Dropping
it means the reviewer trusts the process instead of reading the evidence. That
is the right trade here because the process is enforced and the evidence was
almost always a restatement of the suite that CI runs anyway — but when a change
is verified some way a reviewer genuinely cannot reproduce or infer (a manual
device test, a one-off migration rehearsal, a load run), say so in **What**. The
budget is not a reason to drop something the reviewer actually needs.

**Do NOT clean up worktree** — user needs it alive to iterate on PR feedback.

#### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

**Don't cleanup worktree.**

#### Option 4: Discard

**Confirm first:**
```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for exact confirmation.

If confirmed:
```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
```

Then: Cleanup worktree (Step 6), then force-delete branch:
```bash
git branch -D <feature-branch>
```

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

**For Option 2 (Create PR)**, push and open the segments like this. The other
three options are covered by the table further down.

```bash
# M is the number of rows in the plan's ## PR Segmentation table.
# For row N from 1 to M, read its Branch and Title columns, then:
#   --base is the repository base branch when N is 1,
#   and row N-1's Branch for every later segment.
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

## Follow-ups
<Actions the reader must take outside this PR. If there are none, delete this section and its heading — do not write "None".>
EOF
)"
```

The **Stack:** line lists every segment, not three — write one entry per row in
the table, in order, and mark the one you are opening. For a two-segment stack
opening the second, it reads:

```
**Stack:** 1. Parser · 2. Wiring  ← you are here: 2
```

**Resuming after a failure.** The resume command is the same push-and-create
pair for the segment that failed, with the bases it would have had. If segment 3
of 4 fails, report it like this:

```
Segments 1-2 opened. Segment 3 failed: <the error>.

To resume:
  git push -u origin feat/x-api
  gh pr create --base feat/x-storage --title "[3/4] API" --body "..."

Segment 4 is untouched and still needs opening after 3 lands.
```

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

### Step 6: Cleanup Workspace

**Only runs for Options 1 and 4.** Options 2 and 3 always preserve the worktree.

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree to clean up. Done.

**If worktree path is under `.worktrees/`, `worktrees/`, or `~/.config/umbrella/worktrees/`:** Umbrella created this worktree — we own cleanup.

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git worktree remove "$WORKTREE_PATH"
git worktree prune  # Self-healing: clean up any stale registrations
```

**Otherwise:** The host environment (harness) owns this workspace. Do NOT remove it. If your platform provides a workspace-exit tool, use it. Otherwise, leave the workspace in place.

## Quick Reference

| Option | Merge | Push | Keep Worktree | Cleanup Branch | With a stack |
|--------|-------|------|---------------|----------------|--------------|
| 1. Merge locally | yes | - | - | yes | Merge 1→M, test after each, stop at first failure |
| 2. Create PR | - | yes | yes | - | Push and open 1→M, `--base` chained |
| 3. Keep as-is | - | - | yes | - | Report every segment branch by name |
| 4. Discard | - | - | - | yes (force) | Confirm all branches, delete M→1 |

## Common Mistakes

**Skipping test verification**
- **Problem:** Merge broken code, create failing PR
- **Fix:** Always verify tests before offering options

**Open-ended questions**
- **Problem:** "What should I do next?" is ambiguous
- **Fix:** Present exactly 4 structured options (or 3 for detached HEAD)

**Cleaning up worktree for Option 2**
- **Problem:** Remove worktree user needs for PR iteration
- **Fix:** Only cleanup for Options 1 and 4

**Deleting branch before removing worktree**
- **Problem:** `git branch -d` fails because worktree still references the branch
- **Fix:** Merge first, remove worktree, then delete branch

**Running git worktree remove from inside the worktree**
- **Problem:** Command fails silently when CWD is inside the worktree being removed
- **Fix:** Always `cd` to main repo root before `git worktree remove`

**Cleaning up harness-owned worktrees**
- **Problem:** Removing a worktree the harness created causes phantom state
- **Fix:** Only clean up worktrees under `.worktrees/`, `worktrees/`, or `~/.config/umbrella/worktrees/`

**No confirmation for discard**
- **Problem:** Accidentally delete work
- **Fix:** Require typed "discard" confirmation

**Opening stacked PRs out of order**
- **Problem:** segment N's `--base` points at a branch not yet on the remote, so `gh pr create` fails or the stack reads wrong
- **Fix:** push and open strictly 1 to M; stop at the first failure

**Opening a PR without measuring the diff**
- **Problem:** a 3,000-line PR gets a rubber-stamp review
- **Fix:** run Step 1b first; over 800 lines, report and offer to split

## Red Flags

**Never:**
- Proceed with failing tests
- Merge without verifying tests on result
- Delete work without confirmation
- Force-push without explicit request
- Remove a worktree before confirming merge success
- Clean up worktrees you didn't create (provenance check)
- Run `git worktree remove` from inside the worktree
- Open a pull request without running the Step 1b size check
- Open stacked pull requests out of segment order
- Delete remote branches or close PRs to "clean up" a partially-created stack

**Always:**
- Verify tests before offering options
- Detect environment before presenting menu
- Present exactly 4 options (or 3 for detached HEAD)
- Get typed confirmation for Option 4
- Clean up worktree for Options 1 & 4 only
- `cd` to main repo root before worktree removal
- Run `git worktree prune` after removal
- Measure the diff before offering options
- Report partial stack progress rather than rolling it back
