---
id: narrative.uitool.classes
kind: narrative
---

# Browse the target's loaded classes

## Who this is for

A coding agent reverse-engineering a running app's architecture. The view tree
tells it *what is on screen*; `classes` tells it *what types the app has loaded* —
the private classes a framework registers, the app's own controllers, the helper
classes behind a feature. It is the runtime class browser FLEX put behind a tap,
made into a verb.

## The situation today

`inspect` reflects one live **object** and reads its values. But often the agent
wants the class **as declared**, with no instance in hand: what does
`NSVisualEffectView` inherit from, what private ivars does it carry, what methods
does it declare — or simply, *which classes matching `_NSToolbar` are even loaded
in this app?* That is class-level reflection, and it has to run **inside the
target**, because the set of loaded classes (and their private members) is the
target's, not the inspector's.

## What we're building

One command, `classes`, with two modes over the target's runtime:

- **List** — `--match REGEX` returns the names of the loaded classes whose names
  match, so the agent can discover the private and app-specific types a framework
  or feature registered, without dumping all thirty-thousand.
- **Reflect** — `--class NAME` returns one class's declared shape: its superclass
  chain, its ivars (name + type), its properties, its instance and class methods,
  and the protocols it adopts. Metadata only — no instance, no values, no target
  code run.

Both run in the injected server over the same `RuntimeKit` reflection the rest of
the cluster uses; the CLI does the rest.

## Why this matters

Reproducing a first-party behavior often starts with "what class does this, and
what does it expose?" `classes` lets the agent map an app's type graph — find the
class behind a control, read what it declares, walk its inheritance — as
deterministic JSON, instead of guessing from headers that may not exist for a
private framework.

## What this is NOT

This is not instance inspection (that is `inspect` — values live on an object). It
runs no getters and reads no live state; class reflection is pure metadata. And the
**list** mode requires a `--match` — it will not dump every loaded class, which is
an unbounded read the surface forbids.
