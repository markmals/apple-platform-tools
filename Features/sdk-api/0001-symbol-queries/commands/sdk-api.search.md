---
id: command.sdk-api.search
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api search` — fuzzy symbol search by name

## Synopsis

```
sdk-api search <query> [--module M] [--limit N]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<query>` | string | yes | Name fragment to search for. |
| `--module` | string | no | SDK module to query. Default `AppKit`. |
| `--limit` | int | no | Max results. Default `20`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Rank symbols against the lowercased query by a fixed precedence — exact title
   > title prefix > qualified-name prefix > title contains > qualified-name
   contains — breaking ties by title, and take the first `--limit`.
3. Project each result to `SymbolOut` and emit.

## Output

```jsonc
{
  "query": "<query>",
  "results": [
    { "name": "...", "qualified": "...", "kind": "...", "declaration": "...", "availability": { ... } }
  ]
}
```

Each result follows the `SymbolOut` shape.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no results) | 0 | `{query, results}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `results` array is a successful query, exit 0 — distinct from a load
  failure (exit 64).
- Ranking and tie-breaking are deterministic; equal input yields byte-identical
  output via the AgentCLI contract (`domain.agent-cli`).

## Notes

This is a name-shaped lookup over the symbol graph, not the HIG/pattern search
that `sdk-search` provides. Use it to discover the exact spelling of a symbol;
use `sdk-search` to discover how to accomplish a task.
