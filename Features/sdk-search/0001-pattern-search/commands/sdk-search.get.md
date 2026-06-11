---
id: command.sdk-search.get
kind: command
depends-on: [domain.agent-cli]
---

# `sdk-search get` — full pattern(s) by id

## Synopsis

```
sdk-search get <ids...>
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<ids...>` | string(s) | yes | One or more pattern ids (skill convention: ≤ 3). |

## Behavior

1. Load the embedded corpus.
2. For each id in order, look it up. Found patterns are projected to
   `PatternOutput`; unknown ids are collected as missing.
3. Emit the found patterns: a **single object** when exactly one id was found,
   otherwise a **JSON array** of pattern objects.
4. If any id was missing, write a notice to stderr and exit 1 — the found
   patterns are still printed to stdout first.

## Output

The full pattern shape (`PatternOutput`):

```jsonc
{
  "id": "...",
  "title": "...",
  "summary": "...",
  "category": "...",
  "minMacOS": "...",
  "imports": ["..."],
  "keySymbols": ["..."],
  "swiftCode": "...",
  "pitfalls": ["..."],
  "related": ["..."],
  "replaces": "...",
  "whenToUse": "...",
  "higReference": { "section": "...", "url": "..." }
}
```

One found id → a single object. Two or more found ids → an array of these
objects, in argument order. `minMacOS` and `replaces` are omitted when absent;
`swiftCode` is re-indented to a canonical scale.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| all ids found | 0 | the pattern object / array on stdout |
| some ids missing | 1 | found patterns on stdout; `Pattern(s) not found: <ids>` on stderr |
| all ids missing | 1 | nothing on stdout; `Pattern(s) not found: <ids>` on stderr |
| corpus load failure | 64 | `ValidationError` ("Failed to load embedded corpus: …") on stderr |

## Invariants

- Read-only, side-effect-free, offline.
- A partial result (some found, some missing) still emits the found patterns to
  stdout and exits 1 — the missing ids drive the non-zero exit, not the
  successful ones.
- Single-vs-array shape is decided by the count of **found** ids, not the count
  of requested ids.
- Deterministic JSON via the AgentCLI contract (`domain.agent-cli`).
