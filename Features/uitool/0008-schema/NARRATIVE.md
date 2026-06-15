---
id: narrative.uitool.schema
kind: narrative
---

# Print the output contract

## Who this is for

A coding agent driving `uitool` for the first time — or after an upgrade. Every
verb answers in deterministic JSON, but the agent has to *know* the shape to parse
it: which fields a node carries by default, which need `--include`, what `inspect`
returns, what each exit code means. `schema` is how the agent reads that contract
from the tool itself instead of from prose it may not have.

## The situation today

The output contract lives in the specs (`domain.uitool.node` and friends) and in
the agent's training. That is fine for a human, but an agent at a terminal wants
the contract **inline and machine-readable**: a single command whose output it can
parse to discover the field names, their types, and the exit-code map — so it can
adapt to the installed version rather than assume one.

## What we're building

One static command, `schema`, that prints the tool's output contract as a JSON
object: the fields each record type carries (the view node, the window record, the
`inspect` result), which are default vs `--include`-only, their types, and the
exit-code map the agent branches on. It takes no target and does no injection — it
is a pure description of what the other verbs emit, deterministic and offline.

## Why this matters

An agent that can ask the tool "what do you return?" is robust to version drift and
needs no out-of-band documentation. It learns the box once — the same reason every
verb shares one machine contract — and `schema` makes that contract a first-class,
queryable output rather than tribal knowledge.

## What this is NOT

This is not a live read — no app, no node, no injection. It is not JSON-Schema
validation tooling; it is a concise, self-describing catalog of the output shapes.
And it is not the per-verb `--help` (that documents flags); `schema` documents the
*output*.
