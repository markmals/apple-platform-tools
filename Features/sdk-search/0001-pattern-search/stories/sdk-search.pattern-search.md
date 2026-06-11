---
id: story.sdk-search.pattern-search
kind: story
depends-on: [domain.agent-cli]
---

# Ranked, HIG-grounded framework patterns for a task

**As a** coding agent
**I want** ranked, HIG-grounded framework patterns for a task
**So that** I write idiomatic, current code instead of guessing.

**Independent test:** run `sdk-search search "liquid glass sidebar"` against the
embedded corpus and assert the ranked `results` (each with `id`, `title`,
`category`, `score`) and exit 0; then `sdk-search get <id>` for the top result
and assert the full pattern (code, imports, pitfalls).

## Acceptance Criteria

### Background

- Given the embedded corpus of curated AppKit/framework patterns is compiled in
  and loads on every invocation

### Scenario 1: Searching for a task

<!-- id: scenario.sdk-search.pattern-search.search -->

- Given the corpus is loaded
- When the agent runs `sdk-search search "table drag and drop"`
- Then the tool emits `{query, results: [{id, title, category, summary, minMacOS?, score}], hint}`
  ranked best-first
- And it exits 0

### Scenario 2: Fetching a pattern by id

<!-- id: scenario.sdk-search.pattern-search.get -->

- Given the corpus is loaded
- When the agent runs `sdk-search get glass-effect-view-basic`
- Then the tool emits the full pattern (code, imports, keySymbols, pitfalls,
  higReference, …) as a single object
- And it exits 0

### Scenario 3: Listing the corpus by category

<!-- id: scenario.sdk-search.pattern-search.list -->

- Given the corpus is loaded
- When the agent runs `sdk-search list`
- Then the tool emits `{categories: [{category, patterns: [{id, title, minMacOS?}]}]}`
  grouped by category in corpus order
- And it exits 0

### Scenario 4: Batch search with cross-query dedup

<!-- id: scenario.sdk-search.pattern-search.batch -->

- Given the corpus is loaded
- When the agent runs `sdk-search search "liquid glass" "concentric corners"`
  with multiple quoted queries
- Then the tool emits a `BatchSearchOutput` with one block per query
- And a pattern already shown in an earlier query is dropped from a later one
  unless its score is at least 1.3× the earlier best
- And it exits 0
