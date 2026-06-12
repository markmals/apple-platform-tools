---
id: usecase.uitool.tree-drill-to-sidebar
kind: use-case
depends-on: [command.uitool.tree, domain.uitool.node-id, domain.uitool.node]
---

# Drill from a window down to the message-list sidebar

## Goal

Find the view backing Mail's message-list sidebar by peeling the hierarchy open
one bounded layer at a time, without ever pulling the whole window.

## Actor

A coding agent reverse-engineering Mail's layout (the persona in
[[narrative.uitool.tree]]).

## Preconditions

- The agent is attached to a running Mail process.
- The agent holds a window-root node id from a prior `windows` call.

## Main success path

1. The agent walks the tree from the window root at a shallow depth, projecting
   only `node`, `class`, and `frame` to keep the skim tiny.
2. The result returns the top few structural layers; the branch holding the
   sidebar is flagged `truncated: true` with a non-zero `childCount`, so the
   agent knows there is more below it.
3. The agent re-issues `tree` rooted at that truncated branch's `node` handle,
   again at a shallow depth — descending only the promising branch, ignoring the
   rest of the window.
4. Repeating step 3, the agent reaches a node whose `class` and `frame` identify
   the sidebar; that node is a leaf within the requested depth (`childCount: 0`,
   not truncated), so the agent knows it has bottomed out.
5. The agent issues the per-node deep-read facets of the `node` verb (binding to
   this op at depth 0) on that single survivor handle.

## Variations

- **Branch was complete, not truncated:** if a walked branch returns no
  `truncated` markers, its whole subtree is already in hand — the agent reads it
  directly instead of re-issuing `tree`.
- **Handle went stale between steps:** if the held branch handle no longer
  matches (live mutation, re-attach), the walk fails with a stale-root error
  ([[error.uitool.tree-stale-root]]); the agent re-walks from the window root to mint a
  current handle and resumes.
- **Level was unexpectedly wide:** if a level returns far more nodes than useful,
  the agent sizes the next walk with `--count-only` before paying for the bodies,
  then caps it with `--limit` (default 50) and narrows it with `--where`.

## Postconditions

- The agent holds a current `node` handle for the sidebar view.
- No full-tree dump was ever transferred; total bytes scaled with depth and
  fan-out of the walked branches only.
