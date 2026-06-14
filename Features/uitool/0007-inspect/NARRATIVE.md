---
id: narrative.uitool.inspect
kind: narrative
---

# Inspect a live object

## Who this is for

A coding agent reverse-engineering how a running Mac app is built — and the human
researcher behind it. The cheap-read verbs (`windows` / `tree` / `find` / `node`)
already surface a node's *structural* facts: its real runtime class, frame, font,
material, layer, constraints. But the structural snapshot stops at the surface. The
researcher often needs to go one level deeper: *what are this object's instance
variables actually set to right now? What does this private property return?* That
is the question `inspect` answers.

## The situation today

Everything the cheap-read verbs report is read **without touching the object's own
code** — the walker reads public AppKit geometry and decomposes it into plain data.
That is deliberately safe: it never runs a line of the target's code. But it also
means the agent can see *that* a view is an `NSVisualEffectView` with a sidebar
material, not *what its `_state` ivar holds* or *what its private `-effectiveValue`
getter returns*. Those answers live inside the object, reachable only by reading its
ivar memory or invoking its accessors — inside someone else's process.

## What we're building

One command, `inspect`, that takes a node id and reports that live object's
**instance variables with their current values** and its **class reflection** (the
declared properties, methods, and protocols). Reading ivar memory is a safe,
read-only memory access, so it is the default. Invoking the object's property
**getters** — which runs the target's own code and can block, mutate, or crash it —
is **off by default** and enabled only with an explicit `--invoke` flag, always
under a hard timeout and behind a safety screen that refuses known-dangerous
classes and ivars. The agent can narrow a large object to the ivars or properties
it cares about with a regex, so inspecting a sprawling view controller does not dump
hundreds of fields.

To make this possible the inspected app's server keeps a small **registry** mapping
each node id to the live object it was minted from. A read validates the object is
still the one the id named — same structural place, same runtime class — before it
ever dereferences it, and refuses with a stale-handle error rather than reading a
recycled pointer.

## Why this matters

Reproducing a first-party look in native AppKit often comes down to a value the
public API hides: the exact private state a control is in, the resolved value behind
a computed property, the ivar a framework sets that drives the rendering. `inspect`
is how the agent reads those values directly instead of guessing — while the safety
posture (read ivars freely, invoke getters only on demand and only under a timeout)
keeps it from taking down the very app it is studying.

## What this is NOT

This is not *mutation* — `inspect` never sets an ivar or calls a setter; v1 is
read-only. It is not a structural read (that is `node`/`tree`). And it is not a
general code-execution primitive: getter invocation is narrow, gated, timed, and
safety-screened, not an arbitrary "call any method" surface.
