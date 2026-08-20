# Spec Document Reviewer Prompt Template

Use this template when dispatching a spec document reviewer subagent.

**Purpose:** Verify the spec is complete, consistent, and ready for implementation planning.

**Dispatch after:** Spec document is written to docs/specs/

**Before dispatching:** substitute the bracketed paths, and resolve `$BRIEF_DIR`
to an absolute path in the prompt you send. The reviewer works in the consumer
project, where a repo-relative `assets/change-brief` does not exist. `$BRIEF_DIR`
is `<announced skill base directory>/../../assets/change-brief`;
`${CLAUDE_PLUGIN_ROOT}` is **not** set in the Bash tool environment. If the
catalog cannot be found, say so in the dispatch and have the reviewer grade the
rest — a missing catalog must never block the review gate.

```
Task tool (general-purpose):
  description: "Review spec document"
  prompt: |
    You are a spec document reviewer. Verify this spec is complete and ready for planning.

    **Spec to review:** [SPEC_FILE_PATH]

    ## What to Check

    | Category | What to Look For |
    |----------|------------------|
    | Completeness | TODOs, placeholders, "TBD", incomplete sections |
    | Consistency | Internal contradictions, conflicting requirements |
    | Clarity | Requirements ambiguous enough to cause someone to build the wrong thing |
    | Scope | Focused enough for a single plan — not covering multiple independent subsystems |
    | YAGNI | Unrequested features, over-engineering |
    | Block coverage | Spec blocks 1-23 from `$BRIEF_DIR/BLOCKS.md` — see below |

    ## Block Coverage

    Grade against **spec blocks 1-23 only**. Penalize a missing always-present
    block (1-9). Penalize a change that touches infrastructure with no block 20,
    introduces types with no block 16, alters persisted schema with no block 17,
    adds a called interface with no block 18, or introduces states with no
    block 19.

    You must not penalize the absence of plan blocks 24-27. A spec at the first
    gate cannot contain them.

    ## Calibration

    **Only flag issues that would cause real problems during implementation planning.**
    A missing section, a contradiction, or a requirement so ambiguous it could be
    interpreted two different ways — those are issues. Minor wording improvements,
    stylistic preferences, and "sections less detailed than others" are not.

    Approve unless there are serious gaps that would lead to a flawed plan.

    ## Output Format

    ## Spec Review

    **Score:** <integer 0-100>

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Section X]: [specific issue] - [why it matters for planning]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

**Reviewer returns:** Status, Issues (if any), Recommendations
