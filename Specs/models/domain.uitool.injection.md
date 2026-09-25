---
id: domain.uitool.injection
kind: domain
depends-on: [domain.uitool.node-id, domain.uitool.ipc]
---

# Injection & Postures

The model for getting the `uitool` server into a target process, and what each path requires of the **machine** versus the **target**. Derived from HANDOFF §6 — the load-bearing risk of the whole project.

> **Scope note.** This is the **deferred injection half** of `uitool`. The `doctor` (precondition gate) and `attach` / `detach` (injection lifecycle) commands are absorbed as specs here, but their implementation lands after the cheap-read MVP (`windows` / `tree` / `find` / `node` on the pure `UIToolCore`). The spec is intact and the contract below is binding; only the injector and lifecycle implementation are deferred — including the `UIToolBoot` dylib both postures need, which is why both report as not-yet-usable today (see *Today's state*).

## The reframe (read this first)

macOS gates injection **per target**, and which gate applies depends on **who controls the target's code signing**. There is no single "is this machine ready to inject?" question — there are two, and the cheaper one is the common one.

- For an app **you build and sign** for development, the target itself opts in (a debug build carries `get-task-allow`). Injection into your own app works on a **stock, SIP-enabled Mac** — the same way lldb / Xcode / Reveal / InjectionIII attach to your own builds every day. No machine defanging.
- For an app **you did not sign** — Mail, Finder, a notarized third-party app — there is no per-app opt-in to flip, so the only path is to lower the system protections **machine-wide**. That is the defanged dev box.

The tool was previously documented as if **every** target were hostile and the full system defang were always required. That is the worst case, not the floor. The two postures below name the floor and the ceiling, and `doctor` reports **both** so an agent knows what it can attach to from here.

## Posture 1 — Cooperative (the default dev loop)

**Inspect apps you build and sign for development. SIP / AMFI / library-validation stay ON.**

- **Target.** An app the **user** builds and signs for development. A debug build is signed with `get-task-allow` (Xcode does this by default) — the entitlement by which the app **opts in** to being debugged / injected. Its hardened runtime is off, or it carries `com.apple.security.cs.allow-dyld-environment-variables` + `com.apple.security.cs.disable-library-validation`. The user controls all of this because it is their build.
- **Why it works with SIP enabled.** SIP's debugging restriction only protects **Apple-signed system / restricted** processes. A `get-task-allow` target is honored for task-port access and `dyld` insertion **regardless of SIP** — exactly how lldb / Xcode / Reveal / InjectionIII attach to your own apps on a stock Mac. Library validation and the hardened runtime are **per-process** flags the user sets in their own build, not machine-wide switches.
- **Mechanism (v1 = both cooperative paths).** Two ways in, both shipping in v1 for `get-task-allow` targets:
  - **launch** ([[command.uitool.launch]]) — spawn the target with `DYLD_INSERT_LIBRARIES=<…>/UIToolBoot.dylib` (`posix_spawn`) so the [[domain.uitool.boot]] dylib loads before `main` and starts the [[domain.uitool.server]] ([[domain.uitool.ipc]]). Robust across OS/app updates; **loses the target's current on-screen state** (it is a fresh launch).
  - **attach-to-running** ([[command.uitool.attach]]) — resolve a **running** `get-task-allow` target's task port (lldb-style `task_for_pid`, permitted for your own debuggable same-user process on a stock Mac) and remote-`dlopen` the boot dylib into it. **Preserves the target's live UI state** — the research default. Heavier than launch but a well-trodden technique for your own apps (lldb / Reveal / InjectionIII do it daily); the only genuinely hard, deferred route is the *unrestricted* running-attach into a target you did not sign (see *Attach mechanism*).
- **Machine requirements: NONE beyond the OS.** No `csrutil`, no `nvram boot-args`, no library-validation override, no reboot. You **do** need the **arm64** `UIToolBoot` dylib built: a normal Xcode app is arm64, so the injectable must match arm64. The `-arm64e_preview_abi` boot-arg is **not** involved here — it exists only for third-party arm64e code.
- **Per-target preconditions** (checked at attach / launch, **not** by the machine doctor): the target is debuggable (`get-task-allow`) and, for the launch path, permits dyld env vars; for the **attach-to-running** path the target must also be the **same user** (so `task_for_pid` is permitted without root) and `uitool` itself must be signed with the debugger entitlement (`com.apple.security.cs.debugger`) — the per-process lever that lets it acquire a `get-task-allow` target's task port, the same entitlement lldb carries. `doctor` cannot check the *target* preconditions — it has no target — so they live on `attach` / `launch`, not in the machine report; whether `doctor` surfaces the `uitool`-is-debugger-signed fact (a machine-stable property of the installed binary) is its own call, but it does not change the frozen `cooperative.requires` set below.

## Posture 2 — Unrestricted (arbitrary / system / notarized targets)

**Inspect any app, including system apps. Needs the full machine defang.**

- **Target.** Any app, **including ones the user did not sign** — Mail, Finder, a notarized third-party app. These ship with the hardened runtime + library validation and **no `get-task-allow`**, so there is **no per-app lever to flip**.
- **Why it needs the system-wide defang.** With no per-app opt-in, the only path is to lower the protections machine-wide: SIP disabled, `amfi_get_out_of_my_way=0x1`, library validation disabled, `-arm64e_preview_abi`, and the injectable built **arm64e** to match the system frameworks (the dyld shared cache is arm64e on Apple Silicon).
- **Machine requirements: the full defang stack** (the per-check interpreters below). A **dedicated dev box** that holds no real data; reversible from Recovery.

**The key reframe restated:** the defanged machine is required **only** for non-cooperative targets. For the user's own apps, `uitool` runs on a stock, SIP-enabled Mac.

## The doctor report shape

`doctor` is **pure local detection** — it runs before any injection, opens no IPC socket, contacts no target ([[domain.uitool.ipc]] describes the post-injection wire). It judges each machine-wide check **independently** (a half-configured machine yields an itemized verdict, never a single mystery failure) and groups the verdicts into the two postures, so the report answers "what can I attach to from here?" rather than one undifferentiated boolean.

```
DoctorReport
  cooperative : ModeReport   // inspect your own get-task-allow apps; SIP may stay on
  unrestricted: ModeReport   // inspect any app incl. system; needs the defang
  osBuild     : string?      // not a check; never affects usability

ModeReport
  usable  : bool             // every `requires` check is .ok
  requires: [PreconditionCheck]
  note    : string           // one line: what this posture is for
```

A `ModeReport.usable` is true only when **every** check in its `requires` array passed. `osBuild` is recorded but is **not a check** — precondition validity is OS-build-specific (arm64e injection regresses across Tahoe 26.x), so the build is reported for context but never affects either posture's usability, and it is machine-specific so it is normalized out of snapshot assertions like a session id.

### `cooperative.requires`

| Check | Source | Pass condition | `detail` |
| --- | --- | --- | --- |
| `arch` | `uname -m` | Apple Silicon host (`arm64` / `arm64e`) | the reported arch |
| `injectable-arm64` | filesystem | the **arm64** `UIToolBoot` dylib is present | `present` / `absent` |

> **note** ≈ *"Inspect apps you build and sign for development (get-task-allow). No SIP / AMFI / library-validation changes — your machine is already capable."*

This posture deliberately lists **no** SIP / AMFI / libval / arm64e-ABI check: none of them gate injection into a `get-task-allow` target. The only machine facts that matter are *is this an Apple Silicon host* and *is the arm64 injectable built*.

### `unrestricted.requires`

| Check | Source | Pass condition | `detail` (pass / fail) |
| --- | --- | --- | --- |
| `sip` | `csrutil status` | disabled (Permissive Security) | `disabled` / `enabled` |
| `amfi` | `nvram boot-args` | contains `amfi_get_out_of_my_way=0x1` — **the real gate** | `disabled` / `enforcing` |
| `libval` | LV plist | `DisableLibraryValidation` = true | `disabled` / `enabled` |
| `arm64e-abi` | `nvram boot-args` | contains `-arm64e_preview_abi` | `present` / `absent` |
| `arch` | `uname -m` | Apple Silicon host | the reported arch |
| `injectable-arm64e` | filesystem | the **arm64e** `UIToolBoot` dylib is present | `present` / `absent` |

> **note** ≈ *"Additionally required only to inspect apps you did NOT sign (system / notarized). Dedicated dev box; reversible from Recovery."*

These are exactly the existing per-check interpreters (`sip` / `amfi` / `libval` / `arm64e-abi` / `arch`) — their **frozen `detail` tokens and one-line remedies are unchanged**. What changed is the **grouping** (they now live under `unrestricted`, not in one flat array) and the **injectable split**: the single `uitool-built` check becomes two arch-specific checks, `injectable-arm64` (cooperative) and `injectable-arm64e` (unrestricted), because the cooperative path matches a plain-arm64 app and the unrestricted path matches the arm64e shared cache. A plain-arm64 dylib fails `dyld` **silently** against an arm64e target, and vice versa — so each posture must verify the slice it will actually load.

### Exit code

- **Exit 0** when `cooperative.usable` — the common case is reachable.
- **Exit 6** (`PRECONDITION_FAILED`, [[domain.uitool.ipc]]) otherwise.

**Rationale.** Cooperative is the common case, so its readiness drives the exit code; `unrestricted` being unusable on a stock Mac is the *expected* state, not a failure, and never forces a non-zero exit on its own. The structured error on stderr carries `PRECONDITION_FAILED` ([[error.uitool.doctor-precondition-failed]]).

## Today's state

The injection half (`UIToolBoot` / `UIToolServer`) is **not built yet**, so both `injectable-arm64` and `injectable-arm64e` are honestly **absent** and **neither posture is usable today**. `doctor` therefore exits **6** right now — but the report makes the gap legible: cooperative is blocked **only** by the deferred dylib (`injectable-arm64` absent), **not** by any missing machine defang. An agent reading the report sees that the cooperative path needs no `csrutil` / `nvram` / reboot — just the (deferred) arm64 dylib — and that nothing about this machine has to be weakened to inspect the user's own apps.

This is the load-bearing honesty of the new shape: the floor is "build the arm64 dylib", not "defang your Mac".

## Attach mechanism

| Path | Posture | v1? | Mechanism | Trade-off |
| --- | --- | --- | --- | --- |
| **launch** | cooperative (and unrestricted-relaunch) | **v1** | spawn the target under `DYLD_INSERT_LIBRARIES=…/UIToolBoot.dylib` (`posix_spawn`) | simplest, robust across OS/app updates; **loses current UI state** |
| **task-port attach** | cooperative | **v1** | resolve a **running** `get-task-allow` target's task port (lldb-style `task_for_pid`, same-user, `uitool` debugger-entitled) and remote-`dlopen` the dylib | **preserves live state** — the research default; heavier than launch but a known technique for your own apps |
| **first-party running-attach** | unrestricted | deferred | MIP-style `launchservicesd`-checkin hook + Mach thread-hijack (PAC-signed bootstrap; processor-set task-port route) | preserves live state; brittle, version-fragile, **the hard sub-project** |

Both **cooperative** paths — launch and task-port attach-to-running — ship in v1. Develop the walker / query layers against a self-built non-hardened harness (`SampleAppKit`) via the **launch path** first (zero task-port complexity, fastest loop), then bring up cooperative task-port attach against the same harness so the live-state default works on a stock Mac. The genuinely deferred route is the **unrestricted** running-attach — injecting into a target you did **not** sign (a system / notarized app) via the `launchservicesd` hook — which remains the hard sub-project (HANDOFF M5). The distinction that moved attach-to-running into v1: for **your own** `get-task-allow` app, `task_for_pid` + remote `dlopen` is the everyday lldb path and needs no machine defang; only a target with no per-app opt-in forces the brittle hook.

## Lifecycle

- `attach` → resolve the target → gate on the posture's preconditions → inject → poll (bounded) for the socket → bump the session epoch ([[domain.uitool.node-id]]).
- `detach` → close socket, drop registry.
- Idempotent: a second `attach` on an already-injected target reuses the existing server.
- A post-attach verb that finds no live session surfaces `NOT_ATTACHED` (exit 4) per [[domain.uitool.ipc]] — it never silently re-attaches.

## Invariants

- `doctor` / `sip-preflight` gate **every** injection path; on a failed precondition for the posture being used, exit 6 — never silently proceed. `doctor` never mutates boot security implicitly — remediation requires the explicit `--fix` flag, and `--fix` only touches the **unrestricted** stack (the cooperative posture has nothing to remediate).
- **Cooperative needs no machine defang** — but it is not "no requirements": it still needs a `get-task-allow` target (per-target, checked at attach) and the **arm64** `UIToolBoot` dylib (machine, checked by `doctor`). Do not overclaim it as free; do not under-claim it as needing SIP off.
- **Unrestricted needs the full defang** — SIP off, AMFI boot-arg, libval off, arm64e ABI boot-arg, and an **arm64e** injectable. It is required **only** for targets the user did not sign.
- Each precondition is judged independently; no check is skipped because another failed.
- v1 is read-only — no write/mutation ops.
- **The cooperative arm64 injectable ships with the tool; the unrestricted arm64e slice does not.** The arm64 `UIToolBoot` dylib installs beside `uitool` as a source-built developer tool (Homebrew) — a build output, gitignored, never a committed blob, never embedded in an app you ship. The **arm64e** slice stays dev-box only: it exists to load into apps you did not sign, which is only possible on a machine-wide-defanged box ([[architecture]] → "Dual-use & safety posture").

## Relationships

- [[domain.uitool.boot]] — the dylib both postures load into the target; the foothold whose constructor starts the server. Its `injectable-arm64` / `injectable-arm64e` presence is what `doctor` checks.
- [[domain.uitool.server]] — the in-target unit the boot dylib starts; the thing on the far end of the socket.
- [[domain.uitool.ipc]] — the wire the server speaks, and the `NOT_ATTACHED` error a failed / absent session surfaces.
- [[domain.uitool.node-id]] — the session epoch bumped on `attach` / `launch`.
- Consumed by the `doctor`, `list-apps`, [[command.uitool.launch]], [[command.uitool.attach]], `detach` commands.

## Notes

- `-arm64e_preview_abi` is a single point of failure for the **unrestricted** posture only — perpetually "preview", removable by Apple in any point release. The cooperative posture does not depend on it. Track Apple's dyld / AMFI hardening as an existential dependency of the unrestricted path.
- arm64e injection is actively regressing on Tahoe 26 — pin one 26.x build on the dev box for the unrestricted posture; keep the AX fallback wired. The cooperative posture (plain-arm64 into a `get-task-allow` app) is unaffected by the arm64e regression.
- **The launch path is the v1 bring-up order, not the v1 ceiling.** Oracle development (M0–M4) starts on the launch path against `SampleAppKit` — zero task-port complexity, fastest loop — and cooperative **task-port attach-to-running** follows in the same v1, so the live-state research default ("inspect this app as it sits right now") works on a stock Mac for your own apps. What stays **deferred** is preserving live state for a target you did **not** sign: the *unrestricted* running-attach via the `launchservicesd` hook (HANDOFF M5). Live-state inspection is v1 for cooperative targets and deferred only for non-cooperative ones.
- **`doctor` detects and instructs by default; `doctor --fix` opts into auto-remediation** of the **unrestricted** stack only — running the `nvram boot-args` / `DisableLibraryValidation` `defaults write` commands with sudo. `--fix` echoes each command before running it, never runs implicitly, and cannot complete steps requiring Recovery (SIP via `csrutil`) or a reboot — it sets what it can, then prints exactly which manual steps + reboot remain. There is nothing to `--fix` for the cooperative posture: its only deferred blocker is building the arm64 dylib.
