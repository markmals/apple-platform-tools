---
id: command.sdk-search.list
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search list` — enumerate the corpus by category

## Synopsis

```
sdk-search list [--category C]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `--category` | string | no | Restrict to one category (case-insensitive). |

## Behavior

1. Load the embedded corpus.
2. Walk the patterns in corpus order, grouping by `category`. With `--category`,
   keep only patterns whose category matches case-insensitively.
3. Emit groups in the order each category first appears in the corpus; within a
   group, patterns keep corpus order.

## Output

```jsonc
{
  "categories": [
    {
      "category": "...",
      "patterns": [
        { "id": "...", "title": "...", "minMacOS": "..." }
      ]
    }
  ]
}
```

`minMacOS` is omitted when the pattern is broadly available. Each item carries
no code or pitfalls — `list` is the index; `get` is the detail.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (incl. no matching category) | 0 | `ListOutput` on stdout |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline.
- Category groups and within-group patterns preserve corpus order (not sorted) —
  a stable, deterministic projection.
- An unknown `--category` yields an empty `categories` array, exit 0.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).
