# Plan Document Reviewer Prompt Template

Use this template when dispatching a plan document reviewer subagent.

**Purpose:** Verify the plan is complete, matches the spec, and has proper task decomposition.

**Dispatch after:** The complete plan is written.

**Before dispatching:** substitute the bracketed paths, and resolve `$BRIEF_DIR`
to an absolute path in the prompt you send. The reviewer works in the consumer
project, where a repo-relative `assets/change-brief` does not exist. `$BRIEF_DIR`
is `<announced skill base directory>/../../assets/change-brief`;
`${CLAUDE_PLUGIN_ROOT}` is **not** set in the Bash tool environment. If the
catalog cannot be found, say so in the dispatch and have the reviewer grade the
rest — a missing catalog must never block the review gate.

```
Task tool (general-purpose):
  description: "Review plan document"
  prompt: |
    You are a plan document reviewer. Verify this plan is complete and ready for implementation.

    **Plan to review:** [PLAN_FILE_PATH]
    **Spec for reference:** [SPEC_FILE_PATH]

    ## What to Check

    | Category | What to Look For |
    |----------|------------------|
    | Completeness | TODOs, placeholders, incomplete tasks, missing steps |
    | Spec Alignment | Plan covers spec requirements, no major scope creep |
    | Task Decomposition | Tasks have clear boundaries, steps are actionable |
    | Buildability | Could an engineer follow this plan without getting stuck? |
    | Plan blocks | Blocks 24-27 from `$BRIEF_DIR/BLOCKS.md` — see below |

    ## Plan Block Coverage

    Grade against **plan blocks 24-27 only**:

    - **24** — every task has steps with `- [ ]` checkboxes.
    - **25** — every task carries a `static-verifiable` or `browser-walk-only` tag.
    - **26** — every task carries a `**Depends on:**` line as the first paragraph
      under its heading. Every referenced task must exist, and the dependency set
      must be acyclic. Report dangling references and cycles by task number.
    - **27** — a `## Browser-Walk Inventory` exists with at least one numbered,
      plain-prose case per `browser-walk-only` task.

    ## Calibration

    **Only flag issues that would cause real problems during implementation.**
    An implementer building the wrong thing or getting stuck is an issue.
    Minor wording, stylistic preferences, and "nice to have" suggestions are not.

    Approve unless there are serious gaps — missing requirements from the spec,
    contradictory steps, placeholder content, or tasks so vague they can't be acted on.

    ## Output Format

    ## Plan Review

    **Score:** <integer 0-100>

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Task X, Step Y]: [specific issue] - [why it matters for implementation]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

**Reviewer returns:** Status, Issues (if any), Recommendations
