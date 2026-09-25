---
name: minimal-testing
description: Use when implementing any feature or bugfix, once the change works, to decide which tests to write - the absolute minimum set that proves the change, preferring real calls over mocks
---

# Minimal Testing

## Overview

Build the change first. Then write the fewest tests that prove it works. Then
prove each test can fail.

**Core principle:** A test earns its place only if it fails when the change it
covers is broken. Everything else is weight the codebase carries forever.

Test-first development is not required here, because it grew suites where most
of the code was tests. Those suites were slow to run, painful to refactor, and
their failures rarely meant a user-visible break.

## The Workflow

1. **Implement the change.** Explore freely. Nothing gets deleted for being
   written before its test.
2. **Name the contract.** A contract is what the feature promises, what the bug
   report says is broken, or what the issue asks for. List its behaviors in one
   or two lines each.
3. **Write one test per contract behavior.** Add a test for a corner case only
   when you can name the real caller and the real input that reaches it.
4. **Prove each test bites.** Break the change: revert the fix, or remove the
   line that implements the behavior. Run the test and confirm it FAILS for the
   expected reason. Restore the change and confirm it PASSES. A test that passes
   against broken code proves nothing, so delete or fix it.
5. **Stop.** Do not add tests "to be thorough".

## What to Test

| Work | Minimum set |
|------|-------------|
| Feature | One test per behavior in the contract, run through the public entry point a caller uses. |
| Bug fix | One regression test that reproduces the reported symptom. |
| Refactor | No new tests. Existing tests must still pass. If none cover the refactored path, add one at the public entry point before you start. |
| Trivial code | Nothing. This covers passthroughs, constants, configuration, and accessors with no branching. |

**Prefer one test at the boundary over many tests of the internals.** One test
that calls the real entry point and checks the real outcome replaces a handful
of unit tests. It also survives refactors, because it does not know the
internals.

**Delete tests that became redundant.** When a new boundary test covers what
older narrow tests covered, remove the older tests in the same change.

## Real Calls Over Mocks

Run the real code whenever it is practical. That includes the real database
(local or in-memory), the real filesystem (a temp directory), the real HTTP
handler, and the real parser.

Mock only what you cannot run locally or deterministically:

- A paid or rate-limited third-party API
- The clock, or randomness
- A network service with no local equivalent

When you must mock, mock at the outermost edge (the HTTP client, not your own
service), and assert on the outcome your code produces, not on how many times
the mock was called. If a test needs more mock setup than assertions, replace
it with a test that uses real components.

See `testing-anti-patterns.md` in this directory for the common mock mistakes.

## Anti-Goals

- No coverage percentage is a target.
- A test per function or per file is not a requirement.
- A test that exists only to raise a number gets deleted.
- A test for an input no real caller can produce gets deleted.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I'll test every method to be thorough" | Thorough means every contract behavior, not every method. |
| "This getter could break someday" | Name the caller and the input. If you can't, don't write the test. |
| "I'll mock it to be safe" | A mock hides the behavior you are trying to prove. Run the real thing. |
| "The test passed first time, done" | You have not seen it fail. Break the change and run it again. |
| "More tests is safer" | Tests that never fail for real reasons cost every refactor and catch nothing. |

## Checklist

- [ ] Every behavior in the contract has exactly one test
- [ ] Each test failed with the change broken, and passed with it restored
- [ ] Tests call real code; any mock sits at an external edge and is justified
- [ ] No test covers trivial code or an unreachable input
- [ ] Tests made redundant by this change were deleted
- [ ] The full suite passes with clean output
