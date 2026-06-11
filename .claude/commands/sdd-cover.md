---
description: Show a spec's implementation and which of its tests pass.
argument-hint: <spec-id>
---

# /sdd-cover $ARGUMENTS

You are reporting coverage for a single spec: `$ARGUMENTS`.

## Intent

For a given spec ID, show:

- Where the `// SPEC: <id>` reverse pointer lives in `Sources/`.
- Which tests are tagged with this spec ID (and which scenarios are covered).
- Whether those tests currently pass.
- Whether the implementation carries a `(deviates: <reason>)` marker for this spec.

## Steps

1. **Read the spec.** Confirm the ID exists and read its content (so the report header includes the spec's intent in one line).
2. **Locate the implementation and tests:**
   a. `rg "SPEC: <spec-id>" Sources/` — record matching files.
   b. `rg "scenario.<spec-id>" Sources/` (Swift Testing display names) or the `// [scenario.<id>]` comments (ObjC/XCTest in `RuntimeKit`) — record test files and scenario sub-IDs.
   c. Optionally run the tests filtered to this spec ID (`swift test`, filtered) and record pass/fail.
3. **Emit a table** of impl file × {scenarios covered, status, deviation note}.

## Output format

```
COVERAGE — spec: <spec-id>
==========================
Intent: <one-line summary from the spec>

Impl                                          Scenarios            Status      Notes
--------------------------------------------  -------------------  ----------  ----------
Sources/sdk-api/CheckCommand.swift            present, missing     PASS
Sources/AgentCLI/Envelope.swift               malformed            FAIL        1 untested scenario
```

## Implementation status

Manual until tooling lands. `rg` + `swift test` cover this today, just without aggregation.
