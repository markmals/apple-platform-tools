---
id: command.uitool.schema
kind: command
depends-on: [domain.uitool.node, domain.uitool.ipc, command.uitool.inspect, story.uitool.schema-print]
---

# `uitool schema` — print the output contract

## Synopsis

```
uitool schema [--pretty]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |

No target, no `--snapshot`, no injection — `schema` is a pure static read of the
contract the other verbs emit.

## Behavior

1. Emit the static output contract as one JSON object (see Output) and exit 0.

No app is resolved, no socket opened, no precondition checked — `schema` describes
the tool's output and never touches a target.

## Output

A single JSON object on stdout. Deterministic (stable key order, fixed content for
a given build): the record types the verbs emit, each with its fields, plus the
exit-code map.

```jsonc
{
  "schemaVersion": "1.0.0",                 // the IPC schema version ([[domain.uitool.ipc]])
  "exitCodes": {                            // the closed exit-code map the agent branches on
    "0": "ok (a zero-match query is still 0)",
    "2": "usage / BAD_SELECTOR / UNKNOWN_FIELD / BAD_PREDICATE",
    "3": "app not running / not found",
    "4": "NOT_ATTACHED / injection failed",
    "5": "STALE_NODE",
    "6": "precondition failed",
    "7": "TIMEOUT",
    "8": "schema-version mismatch"
  },
  "records": {                              // one entry per output record type
    "node": {
      "description": "a view-tree node (windows/tree/find/node)",
      "fields": [
        { "name": "node",  "type": "string", "default": true,  "description": "stable node id" },
        { "name": "class", "type": "string", "default": true,  "description": "real runtime class" },
        { "name": "layer", "type": "object|null", "default": false, "include": "layer", "description": "CALayer snapshot" }
        // … the full default + --include field set ([[domain.uitool.node]])
      ]
    },
    "window": { "description": "…", "fields": [ /* … */ ] },
    "inspect": { "description": "ivars + reflection ([[command.uitool.inspect]])", "fields": [ /* … */ ] }
  }
}
```

Each field carries `name`, `type`, a `default` flag (true when the verbs emit it
without `--include`), an optional `include` token (the `--include` facet that turns
it on), and a one-line `description`. The catalog mirrors [[domain.uitool.node]]'s
field table — it is the machine-readable form of that contract.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | the contract object on stdout |

`schema` has no failure mode: it takes no external input and does no I/O beyond
printing. (A malformed flag is ArgumentParser's usage exit, as for any command.)

## Invariants

- **Static and offline.** No app, no node, no socket, no injection — `schema` never
  touches a target and is runnable on any Mac.
- **Deterministic.** Stable key order, fixed content for a given build; same build →
  byte-identical output.
- **Mirrors the node contract.** The `node` record's fields are exactly
  [[domain.uitool.node]]'s default + `--include` set; a field added there is added
  here (a drift guard, not a free-form doc).

## Notes

- **Cost tier: free.** No I/O, no target. The cheapest verb.
- The contract is **authored data**, the machine-readable twin of
  [[domain.uitool.node]] / [[command.uitool.inspect]]; keep it in step with those
  specs and the `Node` / `InspectResult` types (a test asserts the `node` record's
  field names match the projected node's keys).
