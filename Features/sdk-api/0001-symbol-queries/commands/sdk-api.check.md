---
id: command.sdk-api.check
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api check` — does a symbol exist?

## Synopsis

```
sdk-api check <symbol> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<symbol>` | string | yes | Qualified name: `Type` or `Type.member`. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Look up `<symbol>` by exact qualified name. When several declarations share
   the name (overloads, cross-extension redeclarations), the **first** match is
   reported — this is an existence check, not an enumeration.
3. Project the matched symbol (if any) to the `SymbolOut` shape and emit.

## Output

When found:

```jsonc
{
  "query": "<symbol>",
  "exists": true,
  "symbol": {
    "name": "...",
    "qualified": "...",
    "kind": "...",
    "declaration": "...",
    "availability": { "introduced": "...", "deprecated": "...", "obsoleted": "...", "message": "..." }
  }
}
```

`availability` is present only when the symbol carries macOS availability; each
of its fields (`introduced`, `deprecated`, `obsoleted`, `message`) is optional.

When not found:

```jsonc
{ "query": "<symbol>", "exists": false }
```

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| found | 0 | `{query, exists: true, symbol}` on stdout |
| not found | 1 | `{query, exists: false}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- The not-found result is a successful query of a real index, distinguished from
  a load failure by its exit code: `1` (negative answer) vs `64` (could not
  answer). An empty / negative answer is never exit 0 for this verb.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).

## Notes

`check` is the only `sdk-api` verb that exits non-zero on a negative answer, so
an agent can gate code generation on `sdk-api check … && …`. The sibling
list-style verbs (`members`, `availability`, `search`, `enums`) treat an empty
result as success.
