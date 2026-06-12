---
id: error.uitool.node-stale
kind: error
depends-on: [domain.uitool.node-id, domain.uitool.ipc, command.uitool.node, story.uitool.node-stale-detection]
---

# The node id no longer points at the located object

## When this happens

The agent reads a node with `--at NODE`, but the held id no longer resolves to the object it was minted for — because the session was re-attached (the `sessionEpoch` moved), or the tree changed so the structural path now resolves to a different object, or the recorded pointer is no longer a valid object of the recorded class. Per [[domain.uitool.node-id]], the server validates before every deref and refuses to dereference a recycled pointer.

## What the user sees

A `STALE_NODE` failure: a non-zero exit (exit 5 from [[domain.uitool.ipc]]) and a one-line structured JSON error on stderr with a `recover` hint. No node record is emitted on stdout. `STALE_NODE` is the canonical wire code (exit 5), confirmed in [[domain.uitool.ipc]]'s closed error vocabulary.

> `{"code":"STALE_NODE","message":"node 7:w0/cv/sv2/sub0 no longer resolves to the recorded NSVisualEffectView","recover":"re-locate the node with windows/tree/find and read the freshly-minted id"}`

## What the user can do

- **Re-locate the node** — re-run `windows`/`tree`/`find` to mint a fresh node id, then read that id. The breadcrumb form of the id (a sibling `sub0`→`sub1` shift) is often guessable without a full re-search.
- **Do not re-issue the same read** — the same stale id yields the same `STALE_NODE`; re-issuing is the wrong recovery.

## Underlying cause (informational)

- `sessionEpoch` mismatch after `attach`/re-attach.
- Structural path re-walk lands on an object whose `object_getClass` differs from the recorded class.
- `FLEXPointerIsValidObjcObject(ptr)` fails for the recorded pointer.
- The registry was invalidated by `reset`, `detach`, or a key-window change.

## Related

- [[domain.uitool.node-id]] — the validation rules and the `STALE_NODE` contract.
- [[command.uitool.node]] — the verb that surfaces this.
- [[story.uitool.node-stale-detection]] — the observable behavior.
