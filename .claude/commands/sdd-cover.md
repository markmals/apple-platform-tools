---
description: Show which platforms implement a spec and which of their tests pass.
argument-hint: <spec-id>
---

# /sdd-cover $ARGUMENTS

You are reporting coverage for a single spec: `$ARGUMENTS`.

## Intent

For a given spec ID, show:

- Which platforms have a `// SPEC: <id>` reverse pointer (and where).
- Which platforms have tests tagged with this spec ID (and which scenarios are covered).
- Whether those tests currently pass.
- Whether any platforms carry a `(deviates: <reason>)` marker for this spec.

## Steps

1. **Read the spec.** Confirm the ID exists and read its content (so the report header includes the spec's intent in one line).
2. **For each platform** (`web`, `website`, `ios`, `android`, `windows`, `linux`, `cli`, `tui`, `convex`):
   a. `rg "SPEC: <spec-id>"` in `apps/<platform>/` (or `services/convex/`) — record matching files.
   b. `rg "scenario.<spec-id>" / "@Tag(\"spec:<spec-id>\")"` etc. — record test files and scenario sub-IDs.
   c. Optionally run the platform's tests filtered to this spec ID and record pass/fail.
3. **Emit a table** of platform × {impl files, scenarios covered, status, deviation note}.

## Output format

```
COVERAGE — spec: <spec-id>
==========================
Intent: <one-line summary from the spec>

Platform    Impl                                   Scenarios            Status      Notes
----------  -------------------------------------  -------------------  ----------  ----------
web         apps/web/src/items/list.vm.ts       empty, populated     PASS
ios         apps/ios/.../ItemsListVM.swift      empty, populated     PASS
android     apps/android/.../ItemsListVM.kt     empty                FAIL        2 untested scenarios
convex      —                                      —                    N/A         not applicable to backend
```

## Implementation status

Manual until tooling lands. `rg` + the platform test runners cover this today, just without aggregation.
