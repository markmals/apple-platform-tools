---
id: domain.uitool.boot
kind: domain
depends-on: [domain.uitool.injection, domain.uitool.ipc, domain.uitool.server]
---

# Domain: the boot dylib (`UIToolBoot`)

The smallest possible piece of `uitool` that runs inside the target. Its entire
job is to **come up cleanly when loaded and start [[domain.uitool.server]]** — it
is the foothold, not the tool. [[domain.uitool.injection]] pins *how it gets in*
(the postures and mechanisms); this model pins what it *does once there* and the
discipline that keeps it from harming the host or escaping the dev box.

> **Scope note.** This is the **deferred injection half** of `uitool`. The
> cooperative postures both depend on this dylib existing — it is why `doctor`
> reports `injectable-arm64` (and `injectable-arm64e`) as *absent* today
> ([[domain.uitool.injection]] → "Today's state"). Building it is the load-bearing
> floor: "build the arm64 dylib", not "defang your Mac."

## What it is

A standalone dynamic library with a **constructor** and nothing resembling a UI.
It is loaded into the target one of two ways ([[domain.uitool.injection]] attach
mechanism):

- **at launch** — the target is spawned with `DYLD_INSERT_LIBRARIES=…/UIToolBoot.dylib`,
  so dyld loads it before `main` (the `launch` command, [[command.uitool.launch]]);
- **into a running process** — a remote `dlopen` of this dylib in an
  already-running, debuggable target (the `attach` command, [[command.uitool.attach]]).

Either way, **the constructor is the only entry point.** Once it has started the
server, the dylib is inert — it holds the server alive and does nothing else.

## The constructor contract

```c
// SPEC: domain.uitool.boot
__attribute__((constructor)) static void uitool_boot(void) { /* … */ }
```

On load, the constructor must, in order:

1. **Derive the socket path** from the live pid — `/tmp/uitool-<getpid()>.sock`
   ([[domain.uitool.ipc]] transport). The path is computed in-process, never
   passed in, so a stale env var can never point it at the wrong socket.
2. **Start [[domain.uitool.server]]** on a dedicated background thread, which
   binds the socket `chmod 0600` and begins accepting. The server start is what
   creates the socket the CLI polls for at attach/launch
   ([[command.uitool.attach]] step "poll for the socket").
3. **Return immediately.** The constructor must not block — it spawns the server
   thread and returns so the target's own launch (or running run loop) is never
   stalled. No AppKit call, no main-thread work, no I/O beyond binding the socket
   happens on the loading thread.

A constructor that throws, blocks, or touches the main thread is a defect: it
either deadlocks the host or silently fails to load, which surfaces to the agent
as `INJECTION_FAILED` (exit 4) — "the socket never appeared"
([[error.uitool.attach-injection-failed]]). The whole point of the bounded poll
at attach is to turn a silent dylib-load failure into a clean exit 4.

## Two architecture slices

dyld silently refuses a slice that does not match the target's
([[domain.uitool.injection]] — "A plain-arm64 dylib fails `dyld` **silently**
against an arm64e target, and vice versa"). So the dylib ships in two builds, each
gating a different posture:

| Build | Posture | Matches | `doctor` check |
| --- | --- | --- | --- |
| **arm64** | cooperative | a normal Xcode app you build and sign (`get-task-allow`) | `injectable-arm64` |
| **arm64e** | unrestricted | the arm64e dyld shared cache (system / notarized targets) | `injectable-arm64e` |

The v1 cooperative MVP needs only the **arm64** build. The arm64e build is built
the same way with `-arm64e_preview_abi`; it is required only for the unrestricted
posture and inherits that posture's deferral ([[domain.uitool.injection]]).

## Teardown

On `detach`, `dlclose`, or app quit, the dylib stops the server, which closes and
**unlinks** the socket and drops the registry ([[domain.uitool.server]] lifecycle;
[[domain.uitool.ipc]] threading — "on dylib unload: close socket, unlink path,
drop the registry"). A leftover socket from a half-open or crashed session is not
a healthy server to reuse; the next attach treats it as a fresh attach
([[command.uitool.attach]] idempotency invariant).

## Invariants

- **Constructor only; non-blocking; off the main thread.** The dylib does its
  whole job at load time by starting the server thread and returning. It never
  blocks the loader and never touches AppKit on the loading thread.
- **The socket path is derived in-process from the pid.** Never trusted from the
  environment — a stale path is how an agent silently talks to the wrong process.
- **Arch must match the target.** Ship arm64 for cooperative, arm64e for
  unrestricted; a mismatch is a silent dyld no-load, caught only by the bounded
  attach poll as exit 4.
- **Distributed as a build output, never embedded in a shipped product.** The
  arm64 `UIToolBoot.dylib` ships as part of the `uitool` developer tool — built
  from source, installed beside the CLI (e.g. the Homebrew formula), the way any
  debugger installs its helpers. It stays a build output (`.gitignore`d, produced
  on install), never a committed blob, and is never linked into or bundled with an
  app you ship. The **arm64e** slice — the one that loads into apps you did not
  sign — stays dev-box only, because the machine it targets is deliberately
  defanged, not because the file is secret ([[domain.uitool.injection]];
  [[architecture]] → "Dual-use & safety posture").
- **No behavior beyond hosting the server.** Any reflection, walking, or IPC logic
  belongs in [[domain.uitool.server]] / `RuntimeKit`, not here. The dylib is the
  foothold; the moment it grows logic, it has stopped being auditable-at-a-glance.

## Relationships

- [[domain.uitool.injection]] — the postures and the two load mechanisms (launch
  `DYLD_INSERT`, running-process remote `dlopen`); the containment invariant.
- [[domain.uitool.server]] — the unit the constructor starts and holds alive.
- [[domain.uitool.ipc]] — the socket path it derives and the server binds.
- [[command.uitool.launch]] / [[command.uitool.attach]] — the CLI commands that
  cause this dylib to load.

## Notes

- **Why a separate dylib at all, rather than building the server into one image.**
  The boot/server split keeps the foothold (the thing that must load cleanly into
  a foreign process and is auditable in a screenful of C) separate from the server
  (the thing with the walker bridge and the socket protocol). The dylib is what
  dyld and the remote-`dlopen` care about; the server is plain Swift/ObjC behind
  it. The split also lets the arm64/arm64e concern live entirely in how this one
  small image is built.
- **Build, signing, and the `-arm64e_preview_abi` flag are build-script concerns,
  never baked into a product** ([[architecture]] §4.1). This model pins the
  *contract* (constructor behavior, arch match, containment); the codesigning and
  boot-arg mechanics live in the build scripts and `doctor`, not in the manifest.
