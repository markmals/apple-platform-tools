---
id: error.uitool.find-bad-selector
kind: error
depends-on: [domain.uitool.selector, domain.uitool.ipc, command.uitool.find, story.uitool.find-locate]
status: draft
---

# Malformed selector or predicate

## When this happens

The agent passes a `--class` selector or a `--where` predicate that does not parse — an unknown combinator, an unbalanced bracket, an unsupported operator, an attribute the grammar does not address, or an **invalid `Regex` pattern** in a `matches`/`~` operand (the Swift-native `Regex` engine throws at construction). It also covers running `find <app>` with **neither** `--class` nor `--where`, which the surface refuses as a usage error rather than enumerating the whole tree. This is a **usage error**, not a zero-match result: the query never ran against the tree.

## What the user sees

A one-line structured JSON error object on stderr (never a stack trace), and exit code **2** per [[domain.uitool.ipc]].

> `{"error":{"code":"BAD_SELECTOR","message":"unexpected token near '[frame-w>>200]'","recover":"fix the selector/predicate syntax; see the selector grammar"}}`

The wire `error.code` is the canonical string **`BAD_SELECTOR`**, per [[domain.uitool.ipc]]'s error-code vocabulary.

## What the user can do

- Correct the selector / predicate syntax against [[domain.uitool.selector]] and re-run — distinct from a zero-match, where re-issuing the same query is the wrong move.
- If the failure is an invalid regular expression in a `matches`/`~` operand, fix the pattern: the engine is Swift-native `Regex` (case-insensitive, unanchored substring), so a literal substring or a valid `Regex` works; an unbalanced group or a malformed character class throws.
- Drop to a simpler `--class` glob and add `--where` constraints incrementally.
- If you passed neither `--class` nor `--where`, add at least one constraint (to enumerate broadly on purpose, pass an explicit broad selector like `--class '*'` and size it with `--count-only` first).

## Underlying cause (informational)

- The selector parser rejected the structural selector before evaluation.
- The predicate parser rejected the `--where` expression before evaluation.
- A `Regex` pattern in a `matches`/`~` operand failed to construct (the Swift `Regex` initializer threw).
- An attribute referenced in the query is outside the addressable vocabulary (see the attribute-vocabulary section of [[domain.uitool.selector]]).
- No constraint was supplied (`find` requires at least one of `--class` / `--where`).

## Related

- [[command.uitool.find]] — issues exit 2 for this.
- [[domain.uitool.selector]] — the grammar this validates against, including the `Regex` engine for `matches`/`~`.
- [[story.uitool.find-locate]] — scenario `scenario.uitool.find-locate.bad-selector`.
