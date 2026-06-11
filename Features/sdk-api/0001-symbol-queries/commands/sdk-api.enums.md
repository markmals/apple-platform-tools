---
id: command.sdk-api.enums
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api enums` — list an enum type's cases

## Synopsis

```
sdk-api enums <type> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<type>` | string | yes | Enum type name. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Collect the members of `<type>` and keep only those whose kind is an enum
   case (`swift.enum.case`).
3. Project each case to `SymbolOut` and emit. A type with no enum cases yields
   an empty `cases` array, not an error.

## Output

```jsonc
{
  "type": "<type>",
  "cases": [
    { "name": "...", "qualified": "...", "kind": "...", "declaration": "...", "availability": { ... } }
  ]
}
```

Each case follows the `SymbolOut` shape.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no cases) | 0 | `{type, cases}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `cases` array (non-enum type, or enum with no cases) is a successful
  query, exit 0 — distinct from a load failure (exit 64).
- Cases inherit the title-sorted order of `members`.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).
