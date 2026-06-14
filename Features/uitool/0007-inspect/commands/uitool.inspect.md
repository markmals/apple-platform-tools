---
id: command.uitool.inspect
kind: command
depends-on: [domain.uitool.registry, domain.runtime.reflection, domain.uitool.ipc, domain.uitool.node-id, story.uitool.inspect-read]
---

# `uitool inspect` — read a live object's ivars, properties, and reflection

## Synopsis

```
uitool inspect <app> --at <node-id> [--invoke] [--match <regex>] [--fields <fields>] [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target, by pid or bundle id |
| `--at <node-id>` | string | yes | the node to inspect ([[domain.uitool.node-id]]) |
| `--invoke` | flag | no | also invoke property **getters** to read property values. **Off by default** — getters run the target's own code; gated, timed, and safety-screened. See Safety. Default off |
| `--match <regex>` | string | no | narrow `ivars` and `properties` to names matching the Swift-Regex pattern ([[domain.uitool.selector]] grammar), so a large object isn't dumped wholesale. Default: all |
| `--fields <fields>` | string | no | projection path list over the result ([[domain.uitool.node]] `--fields`). Default: the full result |
| `--pretty` / `--no-meta` | flag | no | pretty-print / strip `sessionId` for byte-stable output. Default off |

## Behavior

1. Resolve `<app>` to its live session over the socket ([[domain.uitool.ipc]]); no session is `NOT_ATTACHED` (exit 4).
2. Send the `inspect` op with the node id, the `--invoke` flag, and the `--match` pattern.
3. The server resolves the node id to its live object through the [[domain.uitool.registry]] — re-walking the structural path and passing the four-gate validation (epoch, path, pointer validity, class echo); any failure is `STALE_NODE` (exit 5, [[error.uitool.node-stale]]), never a recycled-pointer read.
4. On the target main thread, under the bounded hop ([[domain.uitool.ipc]]), the server reflects the object via [[domain.runtime.reflection]]: the **ivar values** (safe memory reads), the **class reflection** (declared properties, instance methods, adopted protocols), and — only with `--invoke` — the **property values** from the getters.
5. A value read / getter that exceeds the bound returns `TIMEOUT` (exit 7, [[error.uitool.node-value-timeout]]); the target is left alive.
6. Project the result (deterministic: sorted keys, normalized values — see Output) and emit.

## Output

A single JSON object on stdout. Deterministic: stable key order, **no raw pointers or addresses**, no `-description` invocation in the default (no-`--invoke`) read.

```jsonc
{
  "node": "7:w0/cv/vev0",
  "class": "NSVisualEffectView",
  "ivars": [
    { "name": "_state", "type": "q", "value": 1 },                  // scalar, read from memory
    { "name": "_appearance", "type": "@", "value": { "class": "NSAppearance" } },  // object ivar → class (+ node if a registered view)
    { "name": "_material", "type": "q", "value": 7 }
  ],
  "properties": [
    { "name": "material", "type": "q", "readonly": false },         // metadata; value present only with --invoke
    { "name": "state",    "type": "q", "readonly": false, "value": 1 }   // value shown here because --invoke was passed
  ],
  "protocols": ["NSAccessibilityElement", "NSAppearanceCustomization"],
  "methods": ["material", "setMaterial:", "blendingMode"]
}
```

### Value representation (deterministic, no addresses)

- **Scalar ivars/values** (int / float / bool, by `@encode` type) are carried as the value.
- **Object-typed ivars/values** are carried as `{ "class": "<runtime class>" }`, plus `"node": "<id>"` when the object is a view registered in the [[domain.uitool.registry]] — **never** a raw pointer, and **never** the result of an invoked `-description` (that would run code). A short, bounded string is carried verbatim for `NSString`/`NSNumber`.
- **A raw pointer** is available only via `--fields pointer` (opt-in), never default — pointers are non-deterministic ([[domain.uitool.node-id]]).

## Safety

- **Ivar reads are safe and default.** They read memory at the ivar's offset; no target code runs. Ivars on a class `RuntimeSafety.classIsSafe` rejects, or that `RuntimeSafety.ivarIsSafe` flags, are **skipped** (omitted), never read.
- **Getter invocation is gated behind `--invoke`** and runs the target's own accessor code — it can block, mutate, or crash the host. Each invocation runs on the target main thread under the hard ~500 ms bound ([[domain.uitool.ipc]]); a slow/blocked getter is `TIMEOUT` (exit 7), never a hang. Getters on a `RuntimeSafety`-unsafe class are skipped. v1 invokes **getters only** — never a setter, never an arbitrary method.

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| inspected | 0 | the result object on stdout |
| usage / bad `--match` / missing `--at` | 2 | structured error on stderr |
| not attached | 4 | structured error ([[domain.uitool.ipc]]) |
| stale node id | 5 | structured error ([[error.uitool.node-stale]]) |
| value-fetch / getter timeout | 7 | structured error ([[error.uitool.node-value-timeout]]) |
| schema mismatch | 8 | structured error |

## Invariants

- **Read-only.** `inspect` never sets an ivar or calls a setter; v1 mutates nothing ([[domain.uitool.ipc]] v1 read-only invariant).
- **Validate before deref.** Every resolution passes the four [[domain.uitool.registry]] gates; a stale handle is exit 5, never a recycled-pointer read.
- **No getter without `--invoke`.** The default read runs no target code; getter invocation is explicit, timed, and safety-screened.
- **Deterministic.** Sorted keys, normalized values, no addresses/pointers in the default projection — same object + same flags → byte-identical modulo `sessionId`.

## Notes

- **Cost tier: expensive (value-fetching).** Reserve `inspect` for the few nodes
  the structural verbs flagged as interesting; it resolves a live object and hops to
  main per read. `--invoke` is the most expensive and the only path that runs target
  code — use it deliberately.
- `--match` narrowing is what keeps a sprawling controller readable; the
  [[error.uitool.node-value-timeout]] recovery hint points at it.
- Methods and protocols are class reflection (cheap metadata from
  [[domain.runtime.reflection]]); they describe the class, not the instance, so they
  carry no per-instance value and are unaffected by `--invoke`.
