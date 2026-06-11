---
id: command.sdk-search.search
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search search` — ranked pattern search

## Synopsis

```
sdk-search search <query...> [--max N] [--category C]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<query...>` | string(s) | yes | One query, or multiple quoted queries for batch mode. |
| `--max` | int | no | Max results per query. Default `5`. |
| `--category` | string | no | Restrict results to one category (case-insensitive). |

## Behavior

1. Load the embedded corpus and build the BM25 search engine.
2. Reject an empty query (no positional args) with a `ValidationError`.
3. **Single-query mode** (exactly one positional arg, including a single quoted
   multi-word string): run the search and emit a `SearchOutput`.
4. **Batch mode** (two or more positional args, each a distinct query): run each
   query in order and emit a `BatchSearchOutput` with one block per query.
   Cross-query dedup applies — a pattern already shown in an earlier query is
   omitted from a later one **unless** its score is ≥ 1.3× the best score it
   earned in an earlier query.
5. Scores are rounded to 3 decimal places for stable output.

## Output

Single query → `SearchOutput`:

```jsonc
{
  "query": "<query>",
  "results": [
    { "id": "...", "title": "...", "category": "...", "summary": "...", "minMacOS": "...", "score": 0.0 }
  ],
  "hint": "Call `sdk-search get <id>` for full code, key APIs, imports, and pitfalls."
}
```

Batch (multiple queries) → `BatchSearchOutput`:

```jsonc
{
  "queries": [
    { "query": "<q1>", "results": [ /* SearchHit… */ ] },
    { "query": "<q2>", "results": [ /* SearchHit…, post-dedup */ ] }
  ],
  "hint": "Call `sdk-search get <id>` for full code, key APIs, imports, and pitfalls."
}
```

`minMacOS` is omitted when the pattern is broadly available. The result body
carries no code — the agent calls `get` for the full pattern.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no results) | 0 | `SearchOutput` / `BatchSearchOutput` on stdout |
| empty query | 64 | `ValidationError` ("Provide at least one query.") on stderr |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline (the corpus is compiled in).
- An empty `results` array is a successful query, exit 0 — distinct from the
  usage error of an empty query (exit 64).
- Ranking is deterministic (score desc, id asc tie-break); scores are stable to
  3 decimal places. Output obeys the AgentCLI contract (`domain.agent-cli`).

## Notes

Batch mode is the way to amortize several related task queries in one call; the
cross-query dedup keeps a strongly-shared pattern from repeating across blocks
unless a later query ranks it substantially higher.
