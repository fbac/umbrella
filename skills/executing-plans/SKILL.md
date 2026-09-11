---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
---

# Executing Plans

## Overview

Load plan, review critically, execute all tasks, report when complete.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Note:** Tell your human partner that Umbrella works much better with access to subagents. The quality of its work will be significantly higher if run on a platform with subagent support (such as Claude Code or Codex). If subagents are available, use umbrella:subagent-driven-development instead of this skill.

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns: Create TodoWrite and proceed

### Step 2: Execute Tasks

For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed

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
it that way. A comment that paraphrases the line beneath it is forbidden — it
goes stale on the first edit, and a stale comment is worse than none because a
reader trusts it and is wrong. Write one for a non-obvious constraint, a
workaround for external behavior (link the issue), an alternative you
deliberately rejected and why, an ordering requirement that looks arbitrary, or
a business rule not derivable from the code. Never write narration of the next
line, section-divider banners, changelog comments, or commented-out code.
Public API docstrings are exempt — they are contracts for callers who will
never read the body, not narration of it. The rule covers new code plus
comments on lines you are already editing — rewrite those to a why, or delete
them. Do not sweep the repository for comments to fix; that is not your task.

**Segment branches.** A plan may contain a `## PR Segmentation` table and a step
zero on a task that checks out a branch. Run those steps exactly as written. Do
not create a branch the plan did not name, and do not skip a checkout because
you are "already on a branch".

### Step 3: Complete Development

After all tasks complete and verified:
- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use umbrella:finishing-a-development-branch
- Follow that skill to verify tests, present options, execute choice

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Reference skills when plan says to
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

**Required workflow skills:**
- **umbrella:using-git-worktrees** - Ensures isolated workspace (creates one or verifies existing)
- **umbrella:writing-plans** - Creates the plan this skill executes
- **umbrella:finishing-a-development-branch** - Complete development after all tasks
