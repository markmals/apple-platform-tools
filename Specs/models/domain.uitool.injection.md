---
id: domain.uitool.injection
kind: domain
depends-on: [domain.uitool.node-id, domain.uitool.ipc]
---

# Injection & Preconditions

The model for getting FLEX-mac into a target process, and the precondition stack `doctor` verifies. Derived from HANDOFF §6 — the load-bearing risk of the whole project.

> **Scope note.** This is the **deferred injection half** of `uitool`. The `doctor` (precondition gate) and `attach` / `detach` (injection lifecycle) commands are absorbed as specs here, but their implementation lands after the cheap-read MVP (`windows` / `tree` / `find` / `node` on the pure `UIToolCore`). The spec is intact and the precondition contract is binding; only the injector and lifecycle implementation are deferred.

## Precondition stack (each verified independently)

| Check | Source | Pass condition |
| --- | --- | --- |
| SIP | `csrutil status` | disabled (Permissive Security on Apple Silicon) |
| AMFI | `nvram boot-args` | contains `amfi_get_out_of_my_way=0x1` — **the real gate** |
| Library validation | LV plist | `DisableLibraryValidation` = true |
| arm64e ABI | `nvram boot-args` | contains `-arm64e_preview_abi` |
| arch match | `file` / `lipo` | the dylib is built **arm64e** (a plain-arm64 dylib fails dyld silently) |
| flexmac built | filesystem | `FLEXMac.framework` present |
| target running | process list | the target pid exists |

**SIP-off alone is necessary but NOT sufficient.** Any one link failing silently produces "dylib didn't load"; `doctor` must report exactly which failed plus a one-line remedy (exit 6).

## Attach paths

| Path | Mechanism | Trade-off |
| --- | --- | --- |
| **B** (default) | MIP-style `launchservicesd`-checkin hook + Mach thread-hijack (PAC-signed bootstrap; processor-set task-port route) | preserves live state; brittle, version-fragile, the hard sub-project |
| **A** (`--relaunch`) | relaunch target under `DYLD_INSERT_LIBRARIES` (`posix_spawn`) | simplest, robust across OS/app updates; **loses current UI state** |

Even though Path B is the production default, develop the walker/query layers against a self-built non-hardened harness (`SampleAppKit`) via `--relaunch` (Path A) first — zero injection risk, fast loop — then harden the Path B injector for live first-party targets, one at a time.

## Lifecycle

- `attach` → run preconditions → inject → poll (bounded) for the socket → bump the session epoch ([[domain.uitool.node-id]]).
- `detach` → close socket, drop registry.
- Idempotent: a second `attach` on an already-injected target reuses the existing server.
- A post-attach verb that finds no live session surfaces `NOT_ATTACHED` (exit 4) per [[domain.uitool.ipc]] — it never silently re-attaches.

## Invariants

- `doctor` / `sip-preflight` gate **every** injection path; on any failed precondition, exit 6 — never silently proceed. `doctor` never mutates boot security implicitly — remediation requires the explicit `--fix` flag.
- arm64e is mandatory, not optional, for first-party targets.
- v1 is read-only — no write/mutation ops.
- The signed dylib / framework / CLI are **never distributed** — dev box only; they are an attack tool on any other machine (ARCHITECTURE → "Dual-use & safety posture").

## Relationships

- [[domain.uitool.ipc]] — the server (`UIToolServer`) the injected dylib starts, and the `NOT_ATTACHED` error a failed/absent session surfaces.
- Consumed by the `doctor`, `list-apps`, `attach`, `detach` commands.

## Notes

- `-arm64e_preview_abi` is a single point of failure — perpetually "preview", removable by Apple in any point release. Track Apple's dyld/AMFI hardening as an existential dependency.
- arm64e injection is actively regressing on Tahoe 26 — pin one 26.x build on the dev box; keep the AX fallback wired.
- **Path B (running-attach) is the v1 default** — preserving the target's live UI state is core to the research use case ("inspect Mail as it sits right now"). Path A is available via `--relaunch` for single-instance apps or when a clean-launch state is wanted. **Sequencing implication:** the default path is the fragile Mach/processor-set route, so its risk can't be fully deferred to M5 — oracle development (M0–M4) still uses `--relaunch` against `SampleAppKit`, but the Path B injector must be hardened earlier than a Path-A-default plan would require.
- **`doctor` detects and instructs by default; `doctor --fix` opts into auto-remediation** — running the `nvram boot-args` / `DisableLibraryValidation` `defaults write` commands with sudo. `--fix` echoes each command before running it, never runs implicitly, and cannot complete steps requiring Recovery (SIP via `csrutil`) or a reboot — it sets what it can, then prints exactly which manual steps + reboot remain.
