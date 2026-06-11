---
id: narrative.sdk-search.pattern-search
kind: narrative
---

# HIG-grounded pattern search

## Who this is for

A coding agent (steered by a macOS developer) that knows *which symbols exist*
but not *how to use them well* — the agent needs the canonical, current,
HIG-grounded way to accomplish an AppKit/framework UI task before it writes code.

## The situation today

`sdk-api` tells the agent a symbol exists; it does not tell the agent the
idiomatic way to wire it up. So the agent reconstructs an approach from stale
training data: it reaches for a pre-Liquid-Glass pattern, misses the
concentricity rules, hand-rolls drag-and-drop the deprecated way, or forgets the
pitfalls that only surface at runtime. The result compiles but isn't current,
isn't idiomatic, and doesn't match what the Human Interface Guidelines actually
recommend for this OS.

## What we're building

`sdk-search` is a ranked lookup over an **embedded, curated corpus of ~69
patterns**, each a single canonical answer to a framework UI task: a title, a
summary, the key symbols, runnable Swift, the imports, the pitfalls, the minimum
macOS version, and a Human Interface Guidelines reference. A BM25 search engine
(with name boosts, platform-intent boosts, a relevance floor, and a coverage
gate) ranks patterns against a task query. The agent searches for the task
("liquid glass sidebar", "table drag and drop"), gets a ranked shortlist of
pattern ids with scores, then pulls the full pattern — code and pitfalls
included — by id. A `list` verb enumerates the whole corpus by category, and a
`debug` verb exposes the ranking pipeline for tuning. The corpus is compiled in,
so every query is offline and deterministic.

## Why this matters

The agent writes idiomatic, current, HIG-grounded code instead of guessing. The
canonical pattern — the one an Apple engineer would point to — is a cheap,
offline `search` + `get` away, ranked so the best answer is first and grounded
in the HIG so it reflects current platform guidance, not a training snapshot.

## What this is NOT

- Not a symbol existence/availability check — that is `sdk-api`. This tool
  answers "how do I do X?", not "does Y exist?".
- Not an open-ended web/doc search — it ranks over a fixed, curated corpus, not
  the live internet.
- Not a code generator — it returns curated reference patterns the agent adapts,
  not bespoke generated code.
