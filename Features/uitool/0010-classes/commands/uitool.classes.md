---
id: command.uitool.classes
kind: command
depends-on: [domain.runtime.reflection, domain.uitool.ipc, domain.uitool.selector, story.uitool.classes-browse]
---

# `uitool classes` — browse the target's loaded classes

## Synopsis

```
uitool classes <app> (--match <regex> | --class <name>) [--limit <n>] [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target, by pid or bundle id |
| `--match <regex>` | string | one of | **list mode** — class names matching the Swift-Regex pattern ([[domain.uitool.selector]]) |
| `--class <name>` | string | one of | **reflect mode** — the one class to reflect fully |
| `--limit <n>` | int | no | cap the list mode's returned names. Default 200 |
| `--pretty` / `--no-meta` | flag | no | pretty-print / strip session metadata |

Exactly one of `--match` / `--class` is required — a bare `classes` would dump every
loaded class, the unbounded read the surface forbids.

## Behavior

1. Resolve `<app>` to its live session ([[domain.uitool.ipc]]); no session is `NOT_ATTACHED` (exit 4).
2. **List mode** (`--match`): the server enumerates the target's loaded classes (`objc_copyClassList`), keeps the names matching the regex, sorts them, and returns up to `--limit` with a `truncated` flag.
3. **Reflect mode** (`--class`): the server resolves the name to a loaded class and reflects it via [[domain.runtime.reflection]] — superclass chain, ivars (name + type), properties, instance + class methods, protocols. A name that is not a loaded class returns `loaded: false` (exit 0 — a valid empty result, not an error).
4. Emit the result.

## Output

A single JSON object on stdout. Deterministic: sorted keys and names, no addresses,
no instance values.

**List mode:**

```jsonc
{ "match": "NSVisual", "count": 3, "truncated": false,
  "names": ["NSVisualEffectView", "NSVisualEffectViewBackdrop", "_NSVisualEffectViewBackdropLayer"] }
```

**Reflect mode:**

```jsonc
{
  "class": "NSVisualEffectView",
  "loaded": true,
  "superclasses": ["NSView", "NSResponder", "NSObject"],
  "ivars": [ { "name": "_material", "type": "q" } ],
  "properties": ["material", "state", "blendingMode"],
  "methods": ["material", "setMaterial:"],
  "classMethods": ["defaultAnimationForKey:"],
  "protocols": ["NSAccessibilityElement"]
}
```

Reflection is **declared** members only — what the class itself declares, not
inherited ([[domain.runtime.reflection]]); the inheritance is the `superclasses`
chain. No ivar/property *values* — those need an instance (`inspect`).

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| listed / reflected (incl. 0 matches or `loaded: false`) | 0 | the result on stdout |
| usage / neither flag / bad `--match` regex | 2 | structured error on stderr |
| not attached | 4 | structured error ([[domain.uitool.ipc]]) |
| timeout | 7 | structured error |
| schema mismatch | 8 | structured error |

A 0-match list and an unloaded `--class` are **exit 0** (valid empty results), never
errors — the agent reads `count` / `loaded`, not the exit code.

## Invariants

- **One mode required.** Exactly one of `--match` / `--class`; the list is never
  unbounded (capped by `--limit`, `truncated` when cut).
- **Reflection is metadata, no values, no target code.** Class reflection runs no
  getter and touches no instance ([[domain.runtime.reflection]]).
- **Deterministic.** Sorted names + keys; same target → byte-identical modulo session.

## Notes

- **Cost tier: bounded.** Enumeration is one `objc_copyClassList` walk on the target
  main thread; reflection is one class's metadata.
- Pairs with `inspect`: `classes --class` shows what a type *declares*; `inspect`
  shows what an *instance* currently holds.
