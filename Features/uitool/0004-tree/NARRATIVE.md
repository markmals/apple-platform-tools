---
id: narrative.uitool.tree
kind: narrative
---

# Depth-bounded hierarchy

## Who this is for

A coding agent reverse-engineering a shipping Apple app — Mail, Notes, the
System Settings panes — to reproduce its look and structure, and the human
researcher steering that agent. They cannot see the source; the runtime view
tree is the only ground truth.

## The situation today

The agent can attach to the target and learn that a window exists, but the
moment it wants to understand structure it faces a wall: a real Mail window is
thousands of nested views deep. Dumping the whole tree is hopeless — it blows
the context budget, buries the three views that matter under ten thousand that
don't, and produces output too large to even read. The accessibility tree is no
substitute: it flattens private subclasses into generic roles and hides the
exact nesting the agent is trying to copy. So today the agent either guesses at
structure or drowns in it.

## What we're building

A way to ask for the hierarchy *a little at a time*. The agent names a starting
node and how many levels down it wants; it gets back exactly that slice of the
tree, each node identified by a stable handle it can drill into later. Where the
walk stops because it hit the depth limit, the result says so plainly and notes
how many children were left behind — the agent always knows whether it is
looking at a leaf or at a pruned branch. The agent can also say which facts
about each node it cares about, so a structural skim stays tiny and a detailed
look costs more only when asked for.

## Why this matters

This turns an impossible download into a navigable search. The agent peels the
tree open one bounded layer at a time, follows the branch that looks promising,
and ignores the rest — spending its budget on the part of the app it is actually
trying to understand, never on the whole of it.

## What this is NOT

Not a full-tree export, not a rendered screenshot, and not a per-node deep read:
fonts, layers, and constraints for a single chosen node are separate verbs. This
feature is the structural skeleton and the means to walk it.
