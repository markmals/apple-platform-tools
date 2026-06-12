---
id: domain.uitool.node-id
kind: domain
depends-on: []
---

# Domain: Node ID

A stable, collision-safe handle for a live object across many agent turns. Derived
from HANDOFF §7.3 — the determinism keystone.

## Shape

```
nodeId = "<sessionEpoch>:<structuralPath>#<ptrTag>"
example: 7:w0/cv/sv2/tv0/tr3/c1#a3f9
```

| Segment | Type | Notes |
| --- | --- | --- |
| `sessionEpoch` | int | bumped on `attach`; detects stale handles across re-attach |
| `structuralPath` | string | root-relative child indices (`w0` = window 0, `cv` = contentView, `tv0` = 0th `NSTableView` descendant…). Human/agent-legible — legibility *is* a context-budget feature (the id doubles as a breadcrumb; a sibling `tr3`→`tr4` is often guessable without a round-trip) |
| `ptrTag` | hex | short hash of the object pointer, **for collision detection only, never re-lookup** |

## Identity

- The full `nodeId` identifies an object within a session.
- The pointer is a **field** (`--fields pointer`), never a sort key — pointers are
  non-deterministic.

## Invariants

- **Validate before every deref.** On lookup: (1) re-walk the structural path; (2)
  `FLEXPointerIsValidObjcObject(ptr)`; (3) `object_getClass(ptr) == recordedClass`;
  optionally (4) frame still matches.
- On any mismatch return **`STALE_NODE`** (exit 5) — never dereference a recycled
  pointer. No silent fallback (the only safe behavior, and the repo's code-quality
  rule).
- The registry holds objects **unretained** (weak `NSMapTable`) so it never
  extends host object lifetimes or masks leaks.
- The registry is invalidated on `reset`, on `detach`, and when the key window
  changes.

## Lifecycle

- `attach` → epoch bumped, registry empty.
- A node id is minted lazily when an object is first walked.
- Under live mutation (a table inserting a row) sibling indices shift, so held ids
  for later siblings change — for v1, path-id + a `class` echo for staleness
  detection is enough.

## Relationships

- [[domain.uitool.node]] — carries the `node`/`parent` ids.
- [[domain.uitool.ipc]] — `STALE_NODE` is one of its error codes.

## Notes

- **v1 anchors stability on the structural path + a `class` echo only.** Anchoring
  on `accessibilityIdentifier` (where present) is deferred until churn in the
  target apps' inspection sessions demands it (HANDOFF §13); revisit if held ids
  prove too fragile under live mutation.
- The `STALE_NODE` wire code is **canonical**, not a placeholder — it is the
  confirmed string the [[domain.uitool.ipc]] error envelope emits on a failed
  deref (exit 5).
