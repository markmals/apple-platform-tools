---
id: command.sdk-api.availability
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-api availability` — a symbol's OS availability

## Synopsis

```
sdk-api availability <symbol> [--module M]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<symbol>` | string | yes | Symbol name (title or qualified). |
| `--module` | string | no | SDK module to query. Default `AppKit`. |

## Behavior

1. Load the symbol index for `--module` (extract + cache on first use).
2. Find every symbol whose qualified name matches exactly, or — failing an exact
   match — whose qualified name or title matches case-insensitively. All matches
   are returned (a symbol can have several declarations).
3. Project each match to `SymbolOut` and emit. The macOS availability lives in
   each match's `availability` field.

## Output

```jsonc
{
  "symbol": "<symbol>",
  "matches": [
    {
      "name": "...",
      "qualified": "...",
      "kind": "...",
      "declaration": "...",
      "availability": { "introduced": "...", "deprecated": "...", "obsoleted": "...", "message": "..." }
    }
  ]
}
```

`availability` is present on a match only when that symbol carries macOS
availability; each of its fields is optional.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no matches) | 0 | `{symbol, matches}` on stdout |
| symbol-graph load failure | 64 | `ValidationError` message on stderr (ArgumentParser validation exit) |

## Invariants

- Read-only and side-effect-free apart from populating the symbol-graph cache.
- An empty `matches` array is a successful query, exit 0 — distinct from a load
  failure (exit 64).
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).
