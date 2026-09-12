# Vendored libraries

Committed so a rendered brief opens from `file://` with zero network requests.

| File | Package | Version | sha256 |
|---|---|---|---|
| `marked.min.js` | marked | 12.0.2 | `15fabce5b65898b32b03f5ed25e9f891a729ad4c0d6d877110a7744aa847a894` |
| `mermaid.min.js` | mermaid | 10.9.1 | `61b335a46df05a7ce1c98378f60e5f3e77a7fb608a1056997e8a649304a936d6` |

Both are MIT licensed. `marked.min.js` carries its copyright header inline; mermaid's bundle ships none, so its notice is in `mermaid.LICENSE`.

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
