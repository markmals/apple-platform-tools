---
id: domain.uitool.server
kind: domain
depends-on: [domain.uitool.ipc, domain.runtime.walker, domain.uitool.node, domain.uitool.node-id, domain.uitool.injection]
---

# Domain: the injected server (`UIToolServer`)

The in-target unit that answers the IPC protocol from **inside** the target
process. Where [[domain.uitool.ipc]] pins the *wire* (the bytes on the socket)
and [[domain.uitool.boot]] pins how the code *gets* into the target, this model
pins the server as a **built unit**: where it runs, what it bridges, and the
threading and failure contract it must honor. It is the one piece of `uitool`
that executes in someone else's address space, so its discipline is load-bearing.

> **Scope note.** This is the **deferred injection half** of `uitool`. The
> cheap-read MVP (`windows` / `tree` / `find` / `node`) is built first on the
> pure `UIToolCore` against an offline `Capture`; this spec is the contract the
> live server must satisfy so that the offline and live sources are
> interchangeable behind `SnapshotSource`. The server produces the **same
> `Capture` shape** the offline path reads — that is the whole reason a verb never
> branches on which source answered it.

## What it is

`UIToolServer` is a headless socket server that runs on a **dedicated background
thread** inside the target. It owns three things and nothing else:

1. the per-pid Unix domain socket ([[domain.uitool.ipc]] transport),
2. the request loop that decodes one JSON-Lines request, dispatches it, and
   writes one response (or a stream), and
3. the **bridge** from a wire `op` to a [[domain.runtime.walker]] read, marshaled
   onto the target's main thread.

It holds no policy. Projection, deterministic rounding, key ordering, node-id
stringification, selector matching, and exit-code mapping are all the **CLI's**
job in `UIToolCore` — the server ships *raw* snapshots and lets the pure core
shape them. This keeps the code that runs in a foreign process as small and as
dumb as possible: read on main, serialize off main, send.

## The op → forest snapshot (v1: one read op + ping)

The server is deliberately **dumb**. Every cheap-read `op` ([[domain.uitool.ipc]]
operations) maps to the **same** walker call —
`snapshotApplicationWindows(maxDepth:)` — and the result is wrapped in a `Capture`
(`{epoch, windows}`), the same envelope the offline source decodes from disk. The
**CLI** then does all root-selection, navigation, selector matching, field
projection, depth pruning, and staleness over that `Capture` using the existing
pure verbs ([[domain.uitool.node]], [[domain.uitool.selector]]) — exactly as the
offline `--snapshot` path already does. This is the literal form of the "server
holds no policy" invariant: the server ships a depth-bounded forest; the pure core
shapes it.

| `op` | Server does | `data` payload |
| --- | --- | --- |
| `windows` / `hierarchy` / `find` | `snapshotApplicationWindows(maxDepth:)` | `Capture` whose `windows` is the forest at the requested depth |
| `ping` | none | the handshake object: `schemaVersion` and the session `epoch` |

The `maxDepth` is **computed CLI-side per verb** and sent on the request, so the
forest is bounded to what the verb needs: `windows` sends a shallow depth, `tree`
sends `pathDepth(root) + requestedDepth`, `node` sends `pathDepth(root)`, `find`
sends a deep walk (it must search the whole tree). The server never inspects which
verb is behind the request — it honors the `maxDepth` it is given. The walker
already exists, is `@MainActor`, and is unit-tested on a stock Mac with no
injection ([[domain.runtime.walker]]); the server's only additions are honoring
`maxDepth` and marshaling the call onto the main thread. One code path serves all
four read verbs.

### Node-id resolution and staleness are CLI-side in v1

A `tree`/`node` request names a node-id; the **CLI** resolves its `structuralPath`
and validates the class echo over the returned `Capture` using the same
`NodeTree` / staleness logic the offline path uses — re-walk the path, compare the
recorded class, raise `STALE_NODE` (exit 5) on a mismatch ([[domain.uitool.node-id]]
— "v1 anchors stability on the structural path + a `class` echo only"). The server
does **not** resolve node-ids in v1; pushing resolution server-side (to ship only
a subtree instead of a bounded forest) is a deliberate later optimization (see
Notes), not a v1 concern. The pointer-validity deref is part of the deferred
value-fetching verbs, not the cheap-read path.

## Threading (the load-bearing rule)

[[domain.uitool.ipc]] states the threading invariants as protocol law; this is
the server unit that must enforce them.

- **The accept/read loop never runs on the target's main thread.** It owns its
  own background thread so the host UI stays responsive and a slow agent cannot
  stall the app it is inspecting.
- **Every AppKit read hops to the target main thread**, marshaled per request
  with a bounded wait (the fixed ≈500 ms hop bound, [[domain.uitool.ipc]]). The
  snapshot is built on main; it is plain `Sendable`/`Codable` data
  ([[domain.runtime.walker]]) and is serialized to JSON **off** main.
- **On a hop that exceeds the bound, return `TIMEOUT` (exit 7) — never hang.** A
  busy or modal main thread is a recoverable, reportable state, not a deadlock.
- Per-request main-thread work is tiny and bounded by `maxDepth`. The
  snapshot-image path is avoided entirely (it mutates the hierarchy,
  [[domain.uitool.ipc]]).

## Failure → wire code

The server only ever emits codes from the closed [[domain.uitool.ipc]]
vocabulary; it never invents a code or leaks a stack trace.

| Condition | Wire `error.code` | Exit | Raised by |
| --- | --- | --- | --- |
| main-thread hop (or socket read) exceeds its bound | `TIMEOUT` | 7 | **server** |
| `op` unknown / `v` mismatch | schema/usage per [[domain.uitool.ipc]] | 8 / 2 | **server** |
| node-id path/class echo fails re-validation | `STALE_NODE` | 5 | **CLI** (over the returned `Capture`) |
| requested window/root absent, or a 0-match read | `NO_WINDOWS` on stderr; **exit 0** | 0 | **CLI** |

The server emits only `TIMEOUT` and the schema/usage codes. Staleness
(`STALE_NODE`), empty-result handling (`NO_WINDOWS`), and selector/projection
errors (`BAD_SELECTOR`, `UNKNOWN_FIELD`, `BAD_PREDICATE`) are all raised
**CLI-side** over the returned `Capture` — the matcher, field projection, and
node-id validation are pure `UIToolCore` ([[domain.uitool.selector]],
[[domain.uitool.node]], [[domain.uitool.node-id]]) — so the server never produces
them.

## Determinism boundary

The server is on the **raw** side of the determinism boundary
([[domain.runtime.walker]], [[domain.uitool.node]]): a `CGFloat` crosses the wire
as a full-precision `Double`, children in z-order as walked, no rounding, no key
canonicalization. `UIToolCore` applies `stableRounded`, stable key order, and
node-id stringification over the decoded `Capture`. Two consequences pinned here:

- **The wire is not required to be byte-stable; the CLI's stdout is.** Determinism
  is a property of the projection, not the transport.
- The server **may** attach an optional `pointerTag` per node (a short pointer
  hash, for collision detection only — [[domain.uitool.node-id]]); it is **not
  required** for v1 cheap reads and is **never** used for re-lookup. Omitting it
  yields the same structural id the offline path mints.

## Lifecycle

- **Start.** [[domain.uitool.boot]]'s constructor `dlopen`s and starts the server
  after the dylib loads; the server binds `/tmp/uitool-<pid>.sock`
  ([[domain.uitool.ipc]]) and begins accepting. The session `epoch` it reports in
  `ping` is the one the CLI bumped at attach/launch ([[domain.uitool.node-id]]).
- **Serve.** One request → one response, synchronous and stateless per request;
  the server holds the live object graph but no per-request session state beyond
  the epoch.
- **Stop.** On `detach`, dylib unload, or app quit: stop the loop, close the
  socket, **unlink** its path, drop the registry ([[domain.uitool.ipc]] threading;
  [[domain.uitool.injection]] lifecycle).
- **Idempotent re-attach.** A second attach/launch onto an already-served target
  reuses the running server ([[domain.uitool.injection]] lifecycle); the server
  does not spin up a second socket.

## Invariants

- **The server holds no policy.** Rounding, key order, node-id stringification,
  selector matching, field projection, and exit-code mapping are `UIToolCore`'s —
  the server ships raw `Capture`s. A determinism or projection rule that lives in
  the server is a misplaced concern.
- **AppKit is touched only on main, only within the bound.** No AppKit read off
  the main thread; no unbounded wait on it.
- **v1 is read-only.** No op mutates the target; the value-fetching ops
  (`class`/`ivars`/`value`) that invoke live getters are deferred
  ([[domain.uitool.ipc]] — "default mode: structural, no-invoke").
- **The server is part of the contained injectable.** It ships inside (or beside)
  the signed [[domain.uitool.boot]] dylib, is gitignored, and never enters a
  shippable target or release CI ([[domain.uitool.injection]] containment;
  [[architecture]] → "Dual-use & safety posture").
- **Same `Capture` shape as offline.** Whatever the server sends as a read's
  `data`, the offline `--snapshot` file decodes to the same type, so
  `SnapshotSource` has exactly two interchangeable implementations.

## Relationships

- [[domain.uitool.ipc]] — the wire this server speaks; the closed error vocabulary
  it draws from; the threading law it enforces.
- [[domain.uitool.boot]] — the dylib that loads, `dlopen`s, and starts it.
- [[domain.runtime.walker]] — the `@MainActor` reads every cheap-read `op` bridges
  to; the source of the raw snapshots.
- [[domain.uitool.node]] / [[domain.uitool.node-id]] — the shape the CLI projects
  the server's snapshots into, and the structural staleness check the server runs.
- [[domain.uitool.injection]] — the postures, the attach/launch lifecycle, the
  containment invariant.

## Notes

- **Why all navigation, matching, and resolution stay CLI-side.** The matcher,
  the node-id path resolver, and the field projection are pure `UIToolCore`
  ([[domain.uitool.selector]], [[domain.uitool.node-id]], [[domain.uitool.node]])
  that the offline `--snapshot` path already runs over a `Capture`. Re-running any
  of them in the foreign process would duplicate tested logic across the purity
  boundary for no gain and would put user-supplied regexes/paths inside someone
  else's address space. The server ships a depth-bounded forest; the CLI does the
  rest. This is why one server code path serves all four read verbs.
- **The deferred optimization: server-side subtree resolution.** v1 ships a
  depth-bounded *forest* per read, so a deep `tree`/`node` request transfers more
  than the requested subtree. If a profiling pass shows that is too costly for a
  large target, pushing node-id resolution server-side — so the server walks to
  the requested path and snapshots only that subtree — is the deliberate later
  optimization. It is **not** a v1 concern (research targets are small), and
  taking it must keep the determinism + staleness contract identical. *(deviation
  candidate — record it on the impl if taken.)*
- **The server is tiny on purpose.** Everything hard about `uitool` (the grammar,
  the projection, the determinism, the ranking) lives in the pure core that runs
  on a stock Mac under test. The server is the thin effectful shell the purity
  boundary ([[architecture]] §4.4) is supposed to leave at the edge.
