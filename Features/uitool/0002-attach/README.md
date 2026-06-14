# 0002 — Launch, attach & detach

Getting the inspector into a target process and tearing it down. Three commands:

- **[[command.uitool.launch]]** — start a target **fresh** under inspection (the
  cooperative *launch* path: `posix_spawn` under `DYLD_INSERT_LIBRARIES`). For a
  clean state, or a cold app. `--replace` terminates a running instance first.
- **[[command.uitool.attach]]** — make an **already-running** target inspectable
  **without restarting it** (the cooperative *attach-to-running* path: `task_for_pid`
  + remote `dlopen`), preserving its live on-screen state — the research default.
- **[[command.uitool.detach]]** — close the socket, drop the registry, let the app
  run normally. Never terminates the target.

Each `launch`/`attach` opens the per-pid socket and bumps the session epoch;
`attach` is idempotent (a healthy session is reused), `detach` is idempotent, and
`launch` always starts a fresh session. v1 scope is the **cooperative** posture
(your own `get-task-allow` apps, on a stock Mac) for both launch and attach; the
**unrestricted** running-attach into a target you did not sign (the
`launchservicesd` hook) remains the deferred hard part (HANDOFF M5).

Depends on [[domain.uitool.injection]] (postures, the three mechanisms,
lifecycle), [[domain.uitool.boot]] (the injected dylib), [[domain.uitool.server]]
(the in-target server it starts), and [[domain.uitool.ipc]] (the socket transport
and exit-code mapping). Node ids and the epoch they carry are defined in
[[domain.uitool.node-id]].

## Test oracle — `SampleAppKit`

The effectful injection paths are verified against a self-built, non-hardened
**known-geometry harness** (`SampleAppKit`) — a tiny AppKit app, debug-signed with
`get-task-allow`, built as a **test-support target** (not a shipped product, not in
release CI). It is the oracle every live verb is checked against, so its layout is
a checked-in contract: deterministic, and chosen to exercise the walker fields the
cheap-read verbs project ([[domain.runtime.walker]], [[domain.uitool.node]]).

It is **not** a domain spec (a test harness is not a behavioral contract of the
tool, per `CONVENTIONS.md` → "What is NOT a spec"); its geometry is pinned here and
asserted in the tests. The exact pixel values are the tests' source of truth — what
is contractual is the **set of cases the harness must present**:

| Case the oracle must present | Verb / field it pins |
| --- | --- |
| **Two top-level windows** — a main window (`NSWindow`) and a panel (`NSPanel`), in a known `NSApp.windows` order | `windows` enumeration, the `wN` index basis, `isPanel` |
| **A child window** attached to the main window | `windows` child-window nesting ([[domain.runtime.walker]] child-window-nesting) |
| **An `NSVisualEffectView`** with a known `material` and an `identifier` | `tree`/`node` `material`, `identifier`; `find` by class |
| **A flipped container** (`isFlipped == true`) holding a child with one activated width constraint | `frame` vs `frameTopLeft` + `isFlipped` coordinate flip; `constraintsCount` |
| **A label** (`NSTextField`) with known `text` and a known system `font` (family, size, weight) | `text`, `font` projection |
| **A plain unbacked view** (`wantsLayer == false`) | `layer == null` (not a `present:false` stand-in) |
| *(optional)* **An `NSHostingView` subtree** | `swiftUIBoundary == true` — added when the SwiftUI-boundary scenario is built; the core harness stays pure AppKit to keep it dependency-light |

Representative concrete geometry (illustrative, not frozen): main window content
`{100,100,400,300}` titled `"SampleAppKit"`; a sidebar `NSVisualEffectView`
`material: "sidebar"`, `identifier: "sidebar"`, frame `{0,0,120,300}`; a greeting
`NSTextField` text `"Hello"`, `.systemFont(ofSize: 13)`, `identifier: "greeting"`;
a flipped box `identifier: "flippedBox"` with a child pinned to `width == 200`.

Per [[domain.uitool.injection]], the walker/query layers come up on the **launch**
path against this harness first (M0–M4), then cooperative **attach-to-running** is
brought up against the same harness so the live-state default is exercised end to
end.
