---
id: command.sdk-api.members
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api members` — list a type's members

## Synopsis

```
sdk-api members <type> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<type>` | string | yes | Type name, e.g. `NSGlassEffectView`. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Resolve `<type>` to its container symbol and collect every symbol related to
   it by `memberOf`, sorted by member title.
3. Project each member to `SymbolOut` and emit. An unknown type yields an empty
   `members` array, not an error.

## Output

```jsonc
{
  "type": "<type>",
  "members": [
    { "name": "...", "qualified": "...", "kind": "...", "declaration": "...", "availability": { ... } }
  ]
}
```

Each member follows the `SymbolOut` shape (`name`, `qualified`, `kind`,
`declaration`, optional `availability`).

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. empty members) | 0 | `{type, members}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `members` array (unknown or member-less type) is a successful query,
  exit 0 — distinct from a load failure (exit 64).
- Members are returned in a stable, title-sorted order.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).
