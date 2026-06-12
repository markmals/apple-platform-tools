---
id: error.uitool.tree-stale-root
kind: error
depends-on: [command.uitool.tree, domain.uitool.node-id, domain.uitool.ipc]
---

# Tree root handle is stale

## When this happens

The agent passes `--at` a node handle that no longer matches the live tree — the
object was recycled, the path shifted under live mutation, or the registry was
invalidated (a re-attach, a key-window change). Per [[domain.uitool.node-id]], a stale
handle is never dereferenced.

## What the user sees

The walk does not run. A one-line structured JSON error on stderr, exit 5, with
a `recover` hint. No partial hierarchy on stdout. The stderr line carries
`schemaVersion` (the [[domain.uitool.ipc]] envelope invariant: *every* payload carries
it).

> `{"schemaVersion":"1.0.0","error":{"code":"STALE_NODE","message":"node 7:w0/cv/sv2/sub0 no longer matches the live tree","recover":"re-resolve the path with windows/tree, or re-attach if the session epoch changed"}}`

## What the user can do

- Re-walk from a known-good ancestor — `windows` for a fresh root, then `tree`
  back down to the node — to mint a current handle.
- Compare the epoch prefix in the node id (e.g. the `7` in `7:w0/cv/...`)
  against the `sessionId` field in the current response; a bumped epoch means
  re-attach invalidated every prior handle. (`sessionId` is the wire form of
  node-id's internal `sessionEpoch` integer — [[domain.uitool.ipc]].)
- Re-issuing the identical `--at` is the wrong recovery: it will fail the same
  way, since the handle is what is stale.

## Underlying cause (informational)

- One of [[domain.uitool.node-id]]'s pre-deref validation invariants failed: the
  structural-path re-walk no longer matches, the pointer no longer resolves to a
  live object, or the live class no longer equals the recorded class. (The
  specific checks are defined in [[domain.uitool.node-id]]; this error surfaces their
  failure at the model level.)
- Maps to [[domain.uitool.ipc]]'s `STALE_NODE` → exit 5.

## Related

- [[command.uitool.tree]] — the verb that surfaces this.
- [[story.uitool.tree-walk]] — scenario `scenario.uitool.tree-walk.stale`.
