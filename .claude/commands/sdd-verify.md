---
description: Run the platform's behavioral test suite and report which spec IDs pass.
argument-hint: <platform>
---

# /sdd-verify $ARGUMENTS

You are verifying conformance on a single platform: `$ARGUMENTS` (one of `web`, `website`, `ios`, `android`, `windows`, `linux`, `cli`, `tui`, `convex`).

## Intent

Run all behavioral tests on the target platform and produce a report keyed by spec ID. The report distinguishes:

- **Pass:** every test tagged with the spec ID passed.
- **Fail:** at least one test tagged with the spec ID failed.
- **Missing:** the spec is implemented on this platform (a `// SPEC:` pointer exists) but no tests reference it.
- **Unimplemented:** the spec exists but no `// SPEC:` pointer references it on this platform.

## Steps

1. **Run the platform's test suite** via `mise run -C apps/<platform> test` (or `mise run -C services/convex test` for convex).
2. **Parse the results** by spec ID:
    - Web / website / cli (Vitest): test names start with `[scenario.<id>]`; `describe` blocks carry the parent spec ID.
    - Apple (Swift Testing): `@Suite` carries the spec ID; tests carry `[scenario.<id>]` in the display name.
    - Android (kotlin.test): `@Tag("spec:<id>")` carries the spec ID; `@DisplayName` carries the scenario sub-ID.
    - Windows (MSTest): `[TestCategory("spec:<id>")]` on the class; `[Description("[scenario.<id>] ...")]` on the method.
    - Linux / tui (cargo test): the `#[cfg(test)] mod` carries `// SPEC: <id>`; each `#[test]` has a `// [scenario.<id>]` comment above it.
3. **Cross-reference reverse pointers.** `rg "SPEC: " apps/<platform>/` and parse out the spec IDs to identify implementations without tests.
4. **Cross-reference all known specs.** Walk `specs/` and `features/<n>/` for every spec ID that _could_ be implemented on the target platform.
5. **Output a table** of spec ID → status with a summary count.

## Implementation status

Manual until tooling lands. The platform's `mise run test` works today; the cross-referencing is the missing piece.
