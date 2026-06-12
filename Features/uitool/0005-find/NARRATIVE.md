---
id: narrative.uitool.find
kind: narrative
---

# Find — the cheap "locate few" entry point

## Who this is for

A coding agent reverse-engineering how a first-party Apple app (Mail, Notes, Photos, Music, Finder) achieves its look, and the human researcher steering it. The agent reaches for `find` when it needs to go from "somewhere in this window" to "these one-to-three exact nodes" without ever pulling the tree.

## The situation today

A live Mail window can hold ten thousand nodes. Dumping that tree and grepping it locally would burn the agent's entire context budget on the first call — and the interesting node is almost always a handful of specific instances: the sidebar label, the selected row's text field, the toolbar title. The agent knows roughly _what_ it is looking for (a class, a title substring, a geometry) but not _where_ it sits in the path. It needs a way to ask the running app "how many of these are there, and which ones" and get back only that, cheaply enough to do it repeatedly while it narrows.

## What we're building

`find` lets the agent search the live tree by a class selector, by a predicate expression, or both. It can ask for just the count first — to size a selector before paying for it — then re-run with a result cap and a narrow projection to pull back stable handles plus a few fields for the survivors. The matching and projection happen where the tree lives, so only the matched nodes travel back. The agent then drills into the one or two survivors with the deeper, more expensive read verbs.

## Why this matters

This is the move that makes the whole tool tractable: tree _search_ instead of tree _download_. A find that returns three handles and three frames costs a few hundred bytes; the equivalent local grep would cost a 200k-token tree dump the agent cannot afford. `find` is what the Skill steers toward first, every time.

## What this is NOT

Not a tree walk (`tree` owns depth-bounded traversal) and not a deep read (`node`, `font`, `layer`, `constraints` own single-node detail). Not a query over rendered pixels — snapshots are out of scope. v1 is read-only: `find` never mutates the target.
