---
name: review-lens
description: Use when reviewing a diff, branch, or PR, before declaring work done, requesting code review, or merging — especially changes touching shared surfaces (headers, nav, shells) or auth/route gating, or before finishing a development branch.
---

# Review Lens (Umbrella)

## Overview

A standard code review and a high adversarial score grade **internal quality** — correctness, security, spec-coverage, consistency. They do NOT measure **composed-surface UX**, **cross-feature interaction**, or **runtime feel**. Those are orthogonal axes that diff-level, static review structurally cannot reach. This lens adds the three checks that catch the class of issues a >90 score misses, and enforces that a score is necessary but never sufficient.

Apply this lens **in addition to** normal code review (e.g. `umbrella:requesting-code-review`) — during per-task review and again on the final branch.

**Origin:** W1-D-DASHBOARD scored spec 91 / plan 95 / branch 96, yet the human browser walk found three non-correctness issues none of the reviews reached: a `loading.tsx` render-timing flash, two redundant adjacent operator CTAs, and no logout path for a newly-admitted authed persona. All invisible to static review.

## When to Use

- Reviewing any diff/branch/PR before calling it done or merging.
- Right before `umbrella:finishing-a-development-branch`.
- Any change that touches a shared surface (header, nav, shell, layout) or auth/route gating.

## The Three Checks (do all three, by reading the assembled result — not the diff)

1. **Composed-surface-per-persona.** For every shared surface the change touches, mentally render it **fully assembled for each persona** (every authed state + anon). Reviewers audit the diff; bugs hide in the *composition*. Two locally-correct elements can be globally redundant, contradictory, or leave a persona stranded. Explicitly list each persona's view of the surface.

2. **Cross-feature adjacency.** For every element added or repointed, enumerate the **adjacent elements added by prior shipped work** on the same surface. New + pre-existing frequently collide or duplicate (e.g. a repointed pill landing next to a CTA from an earlier ship, both pointing the same place).

3. **Newly-admitted-persona affordances.** If the change lets a persona reach a surface they previously couldn't, confirm that persona has the essentials there: **log out, get home, navigate, access their own data**. A new admission with no exit is a gap, not a feature.

## Browser-Walk-Only Flagging

Any acceptance criterion that depends on **redirect/render/paint timing** (interaction with `loading.tsx`, streaming, Suspense), **assembled appearance**, or **motion/feel** is `browser-walk-only`. Static review and unit/pgTAP tests cannot confirm it. List every such item explicitly and route it to the human browser walk. Never sign off these on code-reading alone — especially when Playwright can't run locally.

## Score != Ship

A >90 review is necessary, not sufficient — it certifies internal quality, not completeness or runtime feel. Do NOT declare a `browser-walk-only`-class feature done on score alone. The browser walk is the mandatory gate for that class.

## Output

End the review with:
- **Internal-quality verdict** (the normal review result).
- **Composed-surface findings** — per persona, per shared surface.
- **Adjacency findings** — new vs prior-ship elements.
- **Affordance gaps** — any newly-admitted persona missing logout/home/nav/account.
- **Browser-walk inventory** — the walk-only items that still require a human walk before ship.

## Common Mistakes

| Mistake | Reality |
|---|---|
| "Score is 96, it's ready to merge" | Score grades internal quality only. Run the three checks + walk gate. |
| Reviewing the diff, not the rendered surface | Composition bugs live in the assembled result, per persona. |
| Ignoring elements from prior ships | The collision is between your change and code already there. |
| Treating render/redirect timing as testable statically | It isn't. Flag it `browser-walk-only` and walk it. |
