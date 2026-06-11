---
id: command.<tool>.<verb>
kind: command
depends-on: []
---

# `<tool> <verb>` — <short title>

<!--
  A command spec defines the behavior of ONE CLI verb on one tool: its inputs,
  the work it does, the projection it emits, its states, and its exit code.
  It is the pure-core decision logic the CLI wraps — testable against checked-in
  fixtures or a corpus rather than live state. The coding agent is the user;
  keep it machine-first. See the `AgentCLI` contract for the shared JSON/exit-code shape.
-->

## Synopsis

```
<tool> <verb> <args> [--flag …]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<arg>` | <type> | yes/no | <meaning, default> |
| `--<flag>` | <type> | no | <meaning, default> |

## Behavior

<!-- Step by step: resolve inputs → do the work → project → emit. Reference the
     relevant domain model(s) for the data shape; don't restate them. -->

1. <step>
2. <step>

## Output

<!-- The exact stdout shape. A JSON object for scalar queries; JSON-Lines for
     streams. Reference the relevant domain model for field definitions.
     Deterministic: stable key order, fixed precision, no addresses/timestamps
     by default — see the AgentCLI contract. -->

```jsonc
{ ... }
```

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | the payload on stdout |
| <failure> | <2–8> | structured error on stderr (see the relevant error spec) |

## Invariants

- <invariant> (e.g. "read-only and side-effect-free; idempotent")
- <invariant> (e.g. "never exits 0 on failure; an empty result is distinct from an error")

## Notes

<!-- Cost tier (cheap/bounded vs expensive), batching via stdin, anything else. -->
