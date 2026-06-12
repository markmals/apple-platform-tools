---
id: error.uitool.tree-bad-projection
kind: error
depends-on: [command.uitool.tree, domain.uitool.node, domain.uitool.selector, domain.uitool.ipc]
---

# Tree projection or filter is invalid

This spec documents **two distinct error codes** with the same exit code (2):
`UNKNOWN_FIELD` for a malformed projection (`--fields`), and `BAD_PREDICATE` for
a malformed filter (`--where`). They are separate codes so an agent can tell a
typo'd field path apart from a syntactically broken predicate and recover the
right way without guessing.

## When this happens

The agent passes `--fields` a path that is not a field of [[domain.uitool.node]]
(`UNKNOWN_FIELD`), or passes `--where` an expression that does not parse under
[[domain.uitool.selector]] (`BAD_PREDICATE`). Either way the query is malformed
before any walking begins, and the two faults surface as two distinct codes.

## What the user sees

The walk does not run. A one-line structured JSON error on stderr, exit 2, with
a `recover` hint naming the offending token. No hierarchy on stdout. The stderr
line carries `schemaVersion` (the [[domain.uitool.ipc]] envelope invariant:
*every* payload carries it).

An unknown `--fields` path → code `UNKNOWN_FIELD`:

> `{"schemaVersion":"1.0.0","error":{"code":"UNKNOWN_FIELD","message":"unknown field 'frameTopLft' in --fields","recover":"use a field from `uitool schema`; did you mean frameTopLeft?"}}`

A malformed `--where` predicate → code `BAD_PREDICATE`:

> `{"schemaVersion":"1.0.0","error":{"code":"BAD_PREDICATE","message":"--where: unexpected token near 'frame-w >>'","recover":"see the --where grammar in `uitool schema`/selector docs"}}`

The two codes are distinct on the wire so the agent's recovery branch is
unambiguous: `UNKNOWN_FIELD` means fix the projection, `BAD_PREDICATE` means fix
the predicate.

## What the user can do

- On `UNKNOWN_FIELD`: run `uitool schema` to get the exact set of projectable
  field paths, then correct `--fields`.
- On `BAD_PREDICATE`: fix the `--where` expression to the bounded grammar in
  [[domain.uitool.selector]]. A `--where` pattern is matched with Swift-native
  `Regex` (case-insensitive, unanchored substring); a pattern that fails to
  *parse* the predicate grammar is this `BAD_PREDICATE` fault, distinct from a
  pattern that parses but matches nothing (which is a valid, exit-0 empty walk).
- Re-issuing the identical command is the wrong recovery in either case: the
  query string itself is malformed and will fail the same way.

## Underlying cause (informational)

- `UNKNOWN_FIELD`: `--fields` referenced a path absent from the
  [[domain.uitool.node]] schema.
- `BAD_PREDICATE`: `--where` failed to parse under the total expression language
  in [[domain.uitool.selector]] (including an invalid Swift `Regex` pattern,
  which throws at construction and is mapped here).
- Both map to [[domain.uitool.ipc]]'s usage class → exit 2, as two distinct
  `error.code` strings: `UNKNOWN_FIELD` and `BAD_PREDICATE`.

## Related

- [[command.uitool.tree]] — the verb that surfaces both codes.
- [[story.uitool.tree-project]] — scenario `scenario.uitool.tree-project.unknown-field`.
