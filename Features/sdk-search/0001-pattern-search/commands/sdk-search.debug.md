---
id: command.sdk-search.debug
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search debug` — expose the ranking pipeline

## Synopsis

```
sdk-search debug <query...>
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<query...>` | string(s) | yes | Query words, joined into one query. |

## Behavior

A tuning aid that exposes the search pipeline rather than ranked patterns.

1. Load the embedded corpus and build the search engine.
2. Join the positional words into one query string.
3. Run the query through each pipeline stage and capture the intermediate state:
   `preprocess` (synonym substitution) → `tokenize` → `expand` (synonym
   expansion). Also capture the distinct raw tokens (the coverage-gate input).
4. Run the search with a high `max` (20) so the relevance floor does not trim,
   exposing the **unfloored** top-20 scores.

## Output

```jsonc
{
  "query": "<joined query>",
  "preprocessed": "...",
  "tokens": ["..."],
  "expanded": ["..."],
  "rawTokens": ["..."],
  "top": [
    { "id": "...", "title": "...", "score": 0.0, "hasNameBoost": false }
  ]
}
```

`tokens` are the post-preprocess tokens; `expanded` adds synonym expansions;
`rawTokens` are the distinct un-preprocessed tokens, sorted; `top` is the
unfloored top-20 by score, each entry noting whether a name boost applied.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | `DebugOutput` on stdout |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline.
- Output is diagnostic, not a recommendation — the `top` scores are unfloored and
  unfiltered, so they differ from `search` output by design.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).

## Notes

This verb exists to tune the BM25 weights, boosts, floor, and coverage gate by
making the preprocess→tokenize→expand pipeline and the raw scores observable. It
is not part of the agent's normal search-then-get loop.
