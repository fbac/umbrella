# Umbrella

A standalone Claude Code plugin that gives your coding agent a working discipline: brainstorm before building, plan before coding, test before implementing, verify before claiming done.

15 skills, one session-start hook, and a visual change-brief renderer. No runtime dependencies beyond bash and coreutils.

**Score != ship.** A >90 review grades internal quality. It does not grade whether the assembled surface actually works for every persona. Umbrella adds the checks that catch what a clean diff hides.

---

## Install

```
/plugin marketplace add fbac/umbrella
/plugin install umbrella@umbrella
```

Restart the session. The `SessionStart` hook injects the `using-umbrella` skill, which tells the agent to check for a relevant skill before responding to anything.

Works in Claude Code, Copilot CLI, and Cursor — the hook detects the platform and emits the context format each one reads. Tool-name mappings for non-Claude-Code platforms live in `skills/using-umbrella/references/`.

## What it does

Without Umbrella, an agent jumps straight to code. With it, work routes through a pipeline:

```
idea → brainstorming → spec (docs/specs/) → writing-plans → plan (docs/plans/)
     → TDD implementation → code review + review-lens → browser walk → ship
```

Each stage has a gate. Specs go through an adversarial review that must clear 90 before a plan gets written. Plans do the same. Implementation writes the failing test first. Nothing is called "done" without a command run and its output read.

## The skills

**Process — these decide *how* the work happens**

| Skill | Use it when |
|---|---|
| `brainstorming` | Before any creative work. Turns an idea into a spec through dialogue, then runs a persona × surface × affordance completeness pass and an adversarial spec gate. |
| `writing-plans` | You have a spec. Produces a bite-sized task plan written for an engineer with zero context and questionable taste. |
| `systematic-debugging` | Any bug or test failure. Root cause before fixes — symptom patches are failure. |
| `test-driven-development` | Any feature or bugfix. If you didn't watch the test fail, you don't know what it tests. |
| `verification-before-completion` | About to say "done", "fixed", or "passing". Evidence before claims, always. |

**Review**

| Skill | Use it when |
|---|---|
| `review-lens` | Reviewing any diff before merge. The three checks a static review structurally cannot reach — see below. |
| `requesting-code-review` | Dispatches a reviewer subagent with hand-built context, never your session history. |
| `receiving-code-review` | Feedback arrives. Verify before implementing; technical rigor over performative agreement. |

**Execution**

| Skill | Use it when |
|---|---|
| `executing-plans` | Running a written plan in a fresh session with review checkpoints. |
| `subagent-driven-development` | Running a plan in the current session — fresh subagent per task, two-stage review after each. |
| `dispatching-parallel-agents` | 2+ independent tasks with no shared state. |
| `using-git-worktrees` | Feature work needing isolation. Native tools first, git worktrees as fallback. |
| `finishing-a-development-branch` | Implementation is done. Structured merge / PR / cleanup options. |

**Meta**

| Skill | Use it when |
|---|---|
| `using-umbrella` | Loaded automatically every session. Establishes the skill-check-first rule. |
| `writing-skills` | Creating or editing skills. TDD applied to process documentation. |

## Review lens: the three checks

Standard review grades correctness, security, and spec coverage. It cannot see composed-surface UX, cross-feature interaction, or runtime feel. `review-lens` adds:

1. **Composed-surface-per-persona** — render each shared surface fully assembled, for every authed state plus anon. Two locally-correct elements can be globally redundant or leave a persona stranded.
2. **Cross-feature adjacency** — for each element added, enumerate what prior shipped work already put next to it. New and pre-existing collide often.
3. **Newly-admitted-persona affordances** — if a persona can now reach a surface, confirm they can log out, get home, navigate, and reach their own data.

Anything depending on redirect/render/paint timing, assembled appearance, or motion is tagged **browser-walk-only** and routed to a human. It is never signed off on code reading alone.

This came from a real branch that scored spec 91 / plan 95 / branch 96 and still shipped a render-timing flash, two redundant adjacent CTAs, and an authed persona with no logout path.

## Visual change briefs

`assets/change-brief/render.sh` turns a spec (and optionally a plan) into a single self-contained HTML page — rendered markdown plus a Mermaid task dependency graph — so a human can review the shape of a change before any code exists.

```bash
assets/change-brief/render.sh docs/specs/my-feature.md -o docs/briefs/my-feature.html
assets/change-brief/render.sh docs/specs/my-feature.md docs/plans/my-feature.md -o docs/briefs/my-feature.html
```

Omit the plan argument and the Plan section becomes an explicit "not yet written — changes are free right now" callout. That is the spec gate.

Bash and coreutils only; `marked` and `mermaid` are vendored with pinned checksums, so rendering needs no node, no npm, and no network. Output belongs in the consuming project's `.gitignore` — it is derived. `brainstorming` and `writing-plans` call the renderer automatically; if the assets are missing they say so and continue on markdown rather than blocking the gate.

Block catalog and heading conventions: `assets/change-brief/BLOCKS.md`.

## Layout

```
.claude-plugin/   plugin.json, marketplace.json
hooks/            session-start hook + cross-platform polyglot wrapper
skills/           15 skills, each a SKILL.md plus its references
assets/           change-brief renderer, template, vendored JS, tests
docs/             specs and plans for umbrella's own development
```

## Tests

```bash
assets/change-brief/tests/render_test.sh    # shell-level assertions
assets/change-brief/tests/resolve_test.sh   # path resolution
cd assets/change-brief/tests/browser && npm install && node verify.mjs
```

The browser suite is optional (needs `playwright-core`). It exits `2` when no browser is available — a skip, not a pass.

## Contributing

Umbrella is built with its own skills. Changes to a skill go through `writing-skills`: spec first, adversarial review, then subagent testing to confirm the skill actually changes agent behavior. Specs land in `docs/specs/`, plans in `docs/plans/`.

## Credits and license

Forked from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent. All 14 original skills are carried forward; Umbrella adds the completeness pass, the adversarial spec/plan gates, `review-lens`, browser-walk-only tagging, the change-brief renderer, and a standalone session-start bootstrap.

MIT — see [LICENSE](LICENSE).
