---
id: narrative.uitool.node
kind: narrative
---

# Reading one node deeply

## Who this is for

A coding agent reverse-engineering how a first-party macOS app (Mail, Notes, Photos) is built — and the human researcher steering it. The agent has already narrowed a 10k-node window down to one or two interesting nodes; now it needs the full truth about those exact nodes.

## The situation today

The tree and find verbs deliberately return a thin projection — a node's id, real class, frames, a few flags — so a whole window can stream under a context budget. That thinness is the point during search, but it leaves out everything you actually need once you've found the survivor: the class hierarchy, the resolved font, the Auto Layout constraints, the CALayer fills where the look lives, the private ivars. Pulling those for every node would blow the budget; not having a way to pull them at all would make the search pointless. Today the agent can locate a node but can't fully read it.

## What we're building

A way to take one node — identified by the breadcrumb id the agent already holds — and ask for exactly the deeper facets it cares about: any of class, frame, font, constraints, layer, or ivars. The agent names which facets it wants; only those come back, in one small, deterministic record about that single node. It is the last step of the loop the rest of the tool is built around: search the tree cheaply, then read deep on the handful that survived.

## Why this matters

This is where a found node becomes an answer. "What NSView class is the sidebar and what's its layer fill" or "what's the exact font on the selected row" are questions you can only answer by reading one real node deeply. The thin search projections make finding the node affordable; this verb makes the node worth finding.

## What this is NOT

Not a tree walk — it reads one node, never its subtree. Not a search — the node must already be located (via windows/tree/find). The dedicated font, layer, and constraints verbs cover those facets in isolation; this verb is the combined deep read of a single chosen node.
