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
