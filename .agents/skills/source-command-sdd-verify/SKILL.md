---
name: "source-command-sdd-verify"
description: "Run the package's behavioral test suite and report which spec IDs pass."
---

# source-command-sdd-verify

Use this skill when the user asks to run the migrated source command `sdd-verify`.

## Command Template

# /sdd-verify

You are verifying conformance across the package.

## Intent

Run all behavioral tests and produce a report keyed by spec ID. The report distinguishes:

- **Pass:** every test tagged with the spec ID passed.
- **Fail:** at least one test tagged with the spec ID failed.
- **Missing:** the spec is implemented (a `// SPEC:` pointer exists) but no tests reference it.
- **Unimplemented:** the spec exists but no `// SPEC:` pointer references it.

## Steps

1. **Run the test suite** via `mise run test` (the whole package), or `swift test` filtered by spec ID where a narrower run is useful.
2. **Parse the results** by spec ID:
    - Swift Testing (`AgentCLI` and the tools): `@Suite(.spec("<spec-id>"))` carries the spec ID; tests carry the `.scenario("<id>")` trait (`@Test(.scenario("<id>"))`). Grep `\.spec\("` for suites and `\.scenario\("` for scenario tags.
    - ObjC/XCTest (`RuntimeKit`): the test file carries `// SPEC: <id>`; each test method has a `// [scenario.<id>]` comment above it.
    - A single scan over both forms: `rg '\.scenario\("|\[scenario\.'`.
3. **Cross-reference reverse pointers.** `rg "SPEC: " Sources/` and parse out the spec IDs to identify implementations without tests.
4. **Cross-reference all known specs.** Walk `Specs/` and `Features/<tool>/<NNNN>-<slug>/` for every spec ID that _could_ be implemented.
5. **Output a table** of spec ID → status with a summary count.

## Implementation status

Manual until tooling lands. `mise run test` works today; the cross-referencing is the missing piece.
