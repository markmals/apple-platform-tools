---
id: narrative.sdk-api.symbol-queries
kind: narrative
---

# SDK symbol queries

## Who this is for

A coding agent (steered by a macOS developer) that is about to write Swift
against an SDK module — AppKit by default, any module on request — and needs to
know, before it commits a single line, whether a symbol actually exists and what
OS version it requires.

## The situation today

The agent's training data is a snapshot. New SDK symbols (`NSGlassEffectView`,
`effectIsInteractive`) didn't exist when it was trained; old ones may have been
deprecated or obsoleted since. So the agent guesses: it writes code against an
API it half-remembers, the build fails, and the human pays for a round-trip to
discover the symbol was renamed, never existed, or isn't available on the
project's deployment target. Worse than a wrong guess is a confident one — code
that compiles against the installed SDK but crashes on an older OS because the
agent never checked the `@available` floor.

## What we're building

`sdk-api` answers those questions against ground truth: the Swift **symbol
graphs** for an SDK module, the same data the compiler and DocC consume. The
agent asks "does `NSGlassEffectView.effectIsInteractive` exist?", "what are the
members of this type?", "what's the macOS availability of this symbol?", "search
for symbols matching this name", "list the cases of this enum" — and gets a
deterministic JSON answer it can branch on. Symbol graphs are produced on demand
via `swift symbolgraph-extract` and cached under
`~/Library/Caches/sdk-api/<sdkVersion>/<module>/`, so the first query for a
module pays the extraction cost and every query after is fast and offline. The
default module is AppKit; `--module` redirects any query to another SDK module.

## Why this matters

The agent stops writing code against APIs that don't exist or aren't available
on the deployment target. Existence and availability become a cheap, offline
lookup the agent runs *before* generating code, not a compile error it discovers
*after*. The exit code (`exists:false` → exit 1) lets the agent gate on the
answer without parsing prose.

## What this is NOT

- Not documentation prose or usage examples — that is `sdk-search`'s job. This
  tool reports existence, shape, and availability, not how-to.
- Not a type checker or a linter — it answers per-symbol queries, it does not
  validate a whole source file.
- Not limited to AppKit — AppKit is only the default `--module`.
