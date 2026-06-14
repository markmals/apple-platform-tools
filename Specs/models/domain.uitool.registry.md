---
id: domain.uitool.registry
kind: domain
depends-on: [domain.uitool.node-id, domain.uitool.server, domain.runtime.reflection]
---

# Domain: the node registry (live-object resolution)

The server-side map from a [[domain.uitool.node-id]] to the **live object** it was
minted from. The cheap-read verbs never need it — they ship a `Capture` of plain
snapshot values and the CLI navigates that ([[domain.uitool.server]]). But
`inspect` ([[command.uitool.inspect]]) must reach the *actual* `NSObject` to read
its ivar memory or invoke a getter, and a snapshot cannot carry a live object
across the wire. The registry is how the server turns a node id back into the
object — safely.

This realizes the registry [[domain.uitool.node-id]] describes ("the registry holds
objects unretained (weak `NSMapTable`)") as a built unit.

## Shape

```
NodeRegistry
  epoch    : int                     // the session epoch the entries belong to
  byPath   : weak map<structuralPath, NSObject>   // unretained — never extends a lifetime
```

- **Keyed by `structuralPath`** (the [[domain.uitool.node-id]] middle segment, e.g.
  `w0/cv/sv2/tv0`), not by the full id — the epoch is the registry's, and the
  `ptrTag` is for collision detection, never lookup.
- **Values are held weakly** (a `weak NSMapTable` / `NSMapTableWeakMemory`), so the
  registry never retains a host object, never extends its lifetime, and never masks
  a leak ([[domain.uitool.node-id]] invariant).

## Lifecycle

- **Populated lazily during a walk.** When the server walks the live tree to answer
  a read, it registers each visited view's `structuralPath → view`. So by the time
  the agent holds a node id from `tree`/`find`/`windows`, the registry already maps
  it (within the same session).
- **Invalidated** on `detach`, on a session reset, on an `epoch` change, and when
  the key window changes ([[domain.uitool.node-id]] — "the registry is invalidated
  on `reset`, on `detach`, and when the key window changes"). A new epoch starts an
  empty registry.

## Resolution + the validation gate (load-bearing)

Resolving a node id to a live object is **never** a bare map lookup. Before any
dereference, in this order ([[domain.uitool.node-id]] invariant):

1. **Epoch match** — the id's `sessionEpoch` equals the registry's. A mismatch is
   `STALE_NODE` (exit 5, [[error.uitool.node-stale]]); a handle from a prior session
   is never resolved.
2. **Path resolves** — re-walk the `structuralPath` from the window root in the
   **live** tree. If a segment no longer resolves (a row removed, a view torn down),
   `STALE_NODE`.
3. **Pointer validity** — `RuntimeSafety` confirms the resolved pointer is a live
   ObjC object (`FLEXPointerIsValidObjcObject`-equivalent). A recycled or freed
   pointer is `STALE_NODE`, **never** dereferenced.
4. **Class echo** — `object_getClass(obj)` equals the runtime class the id was
   minted against. A pointer reused by a different class is `STALE_NODE`.

Only after all four pass does the object cross into a value-read. No silent
fallback — the only safe behavior, and the repo's code-quality rule.

## Invariants

- **Unretained.** Entries are weak; the registry extends no lifetime and is dropped
  wholesale on invalidation. It is an index, never an owner.
- **Validate before every deref.** All four gates above run on every resolution;
  any failure is `STALE_NODE`, never a guessed read.
- **Re-walk is the source of truth, not the cached pointer.** The structural path is
  re-resolved against the live tree each time; the weak map is a fast path /
  collision check, not the authority. A held id survives only while its structural
  place and class do.
- **Registry lives in the target.** It is part of [[domain.uitool.server]],
  populated on the target's main thread alongside the walk; it never crosses the
  wire. The CLI holds only node-id strings.

## Relationships

- [[domain.uitool.node-id]] — the id scheme, the four-step validation, and the
  invalidation triggers this model realizes.
- [[domain.uitool.server]] — the unit that owns the registry and populates it during
  a walk; resolution runs on the target main thread.
- [[command.uitool.inspect]] — the consumer that resolves a node id to a live object
  to read its ivars / invoke its getters.
- [[domain.runtime.reflection]] — what runs against the resolved object once the
  gate passes.

## Notes

- **v1 anchors on structural path + class echo.** Anchoring on
  `accessibilityIdentifier` is deferred until churn demands it
  ([[domain.uitool.node-id]] notes). The weak-pointer fast path is an optimization;
  correctness comes from the re-walk + class echo.
- The registry is only needed by **value-fetching** (`inspect`). The cheap-read
  verbs deliberately never touch it — keeping the common path free of any live-object
  bookkeeping ([[domain.uitool.server]] "the server holds no policy" for reads).
