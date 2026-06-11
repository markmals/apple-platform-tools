---
id: command.<verb>
kind: command
depends-on: []
---

# `flexscope <verb>` — <short title>

<!--
  A command spec defines the behavior of ONE flexscope CLI verb: its inputs,
  the IPC op it issues, the projection it emits, its states, and its exit code.
  It is the pure-core decision logic the CLI wraps — testable without injection
  by feeding it captured data. The coding agent is the user; keep it machine-first.
-->

## Synopsis

```
flexscope <verb> <args> [--flag …]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<arg>` | <type> | yes/no | <meaning, default> |
| `--<flag>` | <type> | no | <meaning, default> |

## Behavior

<!-- Step by step: resolve → issue IPC op → project → emit. Reference the op in
     domain.ipc and the data shape in domain.node; don't restate them. -->

1. <step>
2. <step>

## Output

<!-- The exact stdout shape. A JSON object for scalar queries; JSON-Lines for
     streams. Reference domain.node for node fields. Deterministic: stable key
     order, z-order children, fixed precision, no addresses/timestamps by default. -->

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
