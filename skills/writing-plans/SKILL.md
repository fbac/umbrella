---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code. Umbrella flavor — use this instead of umbrella:writing-plans.
---

# Writing Plans (Umbrella flavor)

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

> **Umbrella standalone skill** (originally forked from superpowers:writing-plans). Beyond the base flow it adds **walk-tagging** (every task marked `static-verifiable` or `browser-walk-only`) plus a consolidated **Browser-Walk Inventory**, and pins plan output to `docs/plans/`.

**Announce at start:** "I'm using the umbrella:writing-plans skill to create the implementation plan."

**Context:** If working in an isolated worktree, it should have been created via the `umbrella:using-git-worktrees` skill at execution time.

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

**Author with:** the block catalog at `$BRIEF_DIR/BLOCKS.md` — plan blocks 24-28,
and the `### Task <N>:` heading contract that every `**Depends on:**` edge resolves
against. `$BRIEF_DIR` is defined under "Render the Change Brief" below.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

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
generated files (compiled output, minified bundles, code emitted by a schema or
protobuf compiler), lockfiles, vendored dependencies, and `docs/briefs/`.

**Documentation does not count toward the budget.** Prose is read differently
from code and a large doc change does not degrade code review. Exclude README
and guide updates, and exclude the spec and plan documents the change is built
from. Count doc-comments and docstrings that live inside source files, since a
reviewer reads those alongside the code.

This exclusion is for prose *about* a change, not prose that *is* the change.
When the deliverable itself is written text — a skills repository, a
documentation site, prompt or policy files — that text is the code for budget
purposes and counts in full. The question to ask is whether a reviewer has to
read it closely to judge the change, not whether it happens to be markdown.

**Estimating before the code exists.** The plan-time number is a guess and will
be wrong. Estimate from the file structure you already mapped: count the files
you will create or substantially rewrite, and size each against comparable files
already in the repository. Round up, and prefer segmenting when you land near a
threshold — an unnecessary split costs a rebase, a missed one costs a review
nobody can do. The finish-time measurement is the real check; this estimate only
has to be good enough to pick the right shape.

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

**Segments 2 and later** are always a new branch off the previous segment's
branch, so their step zero is always `git checkout -b <branch> <previous-segment-branch>`.
The table above applies only to segment 1.

**Step zero.** Each segment's first task carries a step zero that puts the agent
on the segment branch — the table above for segment 1, the previous-segment
command for segments 2 and later. Because the step
lives in the plan, both execution paths get it without either needing to
understand segmentation as a concept.

**Each segment ships on its own.** At the end of a segment the repository is
green and nothing is half-wired. If a boundary would leave broken state, the
boundary is in the wrong place — move it, do not ship it.

**Shippability outranks the budget.** If you cannot find boundaries that keep
every segment independently shippable at or under the threshold, do not ship a
broken segment to hit a number, and do not silently accept an oversized one.
That combination means the work is not decomposed correctly — say so in the
plan and raise it, because it is a spec problem surfacing late, not a
segmentation exception.

## Walk-Tagging (Umbrella)

**Why this exists:** Static review and unit/pgTAP tests cannot see render/redirect timing, composed-surface UX, or motion/feel. Those are confirmable ONLY in a running browser. If the plan doesn't name them, a feature gets called "done" on a green score while a real issue (e.g. a redirect flash, two redundant adjacent CTAs) ships unseen. Especially critical when Playwright can't run locally — then the human browser walk is the *only* net.

- **Tag every task** `static-verifiable` or `browser-walk-only` in its header. A task is `browser-walk-only` if its acceptance depends on: redirect/render/paint timing (e.g. interaction with `loading.tsx`/streaming/Suspense), the *assembled* appearance of a shared surface per persona, motion/animation, or any "feel" criterion.
- Carry the spec's walk-only tags forward — every spec requirement marked walk-only in brainstorming MUST map to a `browser-walk-only` task here.
- **Browser-Walk Inventory:** add a final section to the plan, `## Browser-Walk Inventory`, listing every `browser-walk-only` item as a numbered walk case in plain prose (account + URL + viewport + action + pass-criterion). This is the script the human executes. Each case is full clear sentences, not shorthand.
- **Meta rule:** score ≠ ship. A >90 plan/branch review is necessary, not sufficient. The browser walk is the mandatory gate for the `browser-walk-only` class; never report such a feature done on score alone.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use umbrella:subagent-driven-development (recommended) or umbrella:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. During per-task and final review, ALSO apply umbrella:review-lens (composed-surface-per-persona + walk-only flagging).

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

Keep the `# … Implementation Plan` H1. `render.sh` strips it when building the
change brief so the merged document has exactly one H1 — this is documented so
nobody "fixes" the H1 away.

## Task Structure

````markdown
### Task N: [Component Name]  — `static-verifiable` | `browser-walk-only`

**Depends on:** Task A, Task B

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

Copy that block verbatim; everything inside it is plan content. Write
`**Depends on:** none` when a task is independent, and put nothing else on that
line. A trailing HTML comment is escaped into the brief as literal text *and*
glues onto the last task id, which then stops looking like a task reference:
measured on a three-task plan whose Task 3 carried `Task 1, Task 2` plus an
"or none" comment, the brief drew Task 1 → Task 3 and silently omitted
Task 2 → Task 3, with no banner and exit 0.

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

**Code shown in plan steps carries no what-comments.** Implementers copy your
code blocks verbatim, so a comment that paraphrases the line beneath it
propagates into the codebase. Comments in plan code explain why, or they are
absent. See umbrella:subagent-driven-development's implementer prompt for the
full rule.

## Remember
- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Walk-tag coverage (Umbrella):** Is every task tagged `static-verifiable` or `browser-walk-only`? Does every spec walk-only requirement map to a `browser-walk-only` task? Is the `## Browser-Walk Inventory` present with one plain-prose case per walk-only item?

**5. Dependency declarations (Umbrella):** Does every task carry a `**Depends on:**` line as the first paragraph under its heading? Does every referenced task exist? Is the dependency set acyclic?

**6. PR segmentation (Umbrella):** Is there a `## PR Segmentation` section? Does
the total estimate respect the budget — segmented if over 800, justified if
between 400 and 800? Does every segment after the first base on its predecessor?
Does each segment's first task carry a step zero?

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Adversarial Plan Review (Umbrella gate)

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

### Opening the Brief

**Every render ends with an open offer.** A path in a transcript is not a click,
and a brief nobody opens is a review gate that did not happen. In the same
message that reports the render — the first pass **and every re-render after a
change round** — offer to open it and give the manual command:

> "Rendered to `<brief path>`. **Want me to open it?** Or open it yourself:
> `open <brief path>` on macOS, `xdg-open <brief path>` on Linux,
> `start <brief path>` on Windows, or paste `file://<absolute brief path>` into
> your browser."

Run the platform opener only after the user says yes. Never open it unasked.

## User Review Gate

After the brief renders, ask the user to review the plan before offering any
execution option:

> "Plan written and saved to `<path>`, and rendered to `<brief path>`. **Want me to open it?** Or open it yourself: `open <brief path>` on macOS, `xdg-open <brief path>` on Linux, `start <brief path>` on Windows, or paste `file://<absolute brief path>` into your browser. Open the brief in your browser and review it — the index on the left navigates the tasks, and the dependency graph shows the order they unlock in. **Changing the plan still costs only a plan rewrite right now**; once execution starts the same change costs code. Let me know if you want changes before we pick an execution mode."

Wait for the user's response. If they request changes, make them and re-run the
plan review loop. Only proceed to the Execution Handoff once the user approves.

## Execution Handoff

After saving the plan, offer execution choice:

**"Plan complete and saved to `docs/plans/<filename>.md`, rendered to `docs/briefs/<filename>.html`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use umbrella:subagent-driven-development
- Fresh subagent per task + two-stage review; apply `umbrella:review-lens` in the review stage

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use umbrella:executing-plans
- Batch execution with checkpoints for review

**Always, after all tasks:** the `## Browser-Walk Inventory` is the mandatory human gate for `browser-walk-only` items. Do not declare the feature done on green tests + >90 review alone.
