---
id: command.uitool.doctor
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, story.uitool.doctor-preconditions]
---

# `uitool doctor` — report what you can inject into from here

## Synopsis

```
uitool doctor [--fix]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| (none) | — | — | `doctor` takes no target; it inspects only the local machine. |
| `--fix` | flag | no | Opt into sudo auto-remediation of the remediable **unrestricted-mode** checks ([[domain.uitool.injection]]). Off by default — `doctor` detects and instructs unless `--fix` is passed. Echoes each command before running it, never runs anything implicitly, and stops at steps that need Recovery (SIP via `csrutil`) or a reboot, printing exactly which manual steps remain. The cooperative posture has **nothing for `--fix` to remediate** — it requires no machine state change (see below). |

There is no `--json` flag: JSON is the only output. The consumer is a coding agent, not a human at a TTY, so output is always deterministic JSON on stdout ([[architecture]]) — there is no human-readable mode to toggle.

## The two injection postures

macOS gates injection **per target**, and which gate applies depends on **who controls the target's code signing**. `doctor` reports **both** postures so an agent knows what it can attach to from here — not one machine-wide pass/fail verdict that treats every target as hostile.

### Cooperative — inspect apps you build and sign (the default dev loop)

The target is an app **the user builds and signs for development**. A debug build is signed with `get-task-allow` (Xcode does this by default) — the entitlement by which the app **opts in** to being debugged and injected. Its hardened runtime is off, or it carries `com.apple.security.cs.allow-dyld-environment-variables` + `com.apple.security.cs.disable-library-validation`. The user controls all of this because it is their build.

This works on a **stock, SIP-enabled Mac**. SIP's debugging restriction protects only Apple-signed system/restricted processes; a `get-task-allow` target is honored for task-port access and dyld insertion **regardless of SIP** — exactly how `lldb` / Xcode / Reveal / InjectionIII attach to your own apps on a stock machine. Library validation and the hardened runtime are **per-process** flags the user sets in their own build, not machine-wide gates.

The v1 mechanism is **launch**: spawn the target with `DYLD_INSERT_LIBRARIES=<…>/UIToolBoot.dylib` so the boot dylib loads at launch and `dlopen`s the server. (A running `get-task-allow` target can also be attached via its task port, `lldb`-style, with the dylib remote-loaded — heavier, a later slice.) A normal Xcode app is **arm64**, so the injectable must be the **arm64** `UIToolBoot` — the `-arm64e_preview_abi` boot-arg is **not** involved here; it exists only for third-party arm64e code.

**Machine requirements: none beyond the OS.** No `csrutil`, no `nvram` boot-args, no library-validation override, no reboot. The two requirements `doctor` checks here are an Apple Silicon host and the **arm64** `UIToolBoot` injectable being present. The per-**target** preconditions (the target is `get-task-allow`, and for the launch path permits dyld env vars) are checked at attach/launch time against a named target — **not** by this machine doctor.

### Unrestricted — inspect apps you did NOT sign (system / notarized)

The target is **any** app, including ones the user did not sign — Mail, Finder, a notarized third-party app. These ship with the hardened runtime + library validation and **no `get-task-allow`**, so there is **no per-app lever to flip**. The only path is to lower the protections **machine-wide**: SIP disabled, `amfi_get_out_of_my_way=0x1`, library validation disabled, `-arm64e_preview_abi`, and the injectable built **arm64e** to match the system frameworks (the shared cache is arm64e on Apple Silicon).

**Machine requirements: the full defang stack** — the existing per-check interpreters. This is a dedicated dev box that holds no real data, reversible from Recovery.

> **The reframe.** The defanged machine is required **only** for non-cooperative targets. For the user's own apps, `uitool` runs on a stock, SIP-enabled Mac. `doctor` was previously documented as if every target were hostile — that is the **worst case, not the floor**.

## Behavior

`doctor` is **pure local detection** — it runs before any injection and does **not** open the IPC socket or contact a target ([[domain.uitool.ipc]] describes the post-injection wire protocol, which this command does not use). It evaluates the **machine-wide** subset of the precondition stack defined in [[domain.uitool.injection]], judging **each check independently** so a half-configured machine yields an itemized verdict rather than a single mystery failure, then **groups** those checks into the two postures:

1. Evaluate each machine-wide precondition independently — every check in the stack except `target running`, which requires a named target `doctor` does not take, and the per-target `get-task-allow` / dyld-env preconditions, which are checked at attach time.
2. Group the checks into two `ModeReport`s — **cooperative** and **unrestricted** — each carrying its own `requires` set and a `usable` flag that is true only when **every** check it requires passes.
3. For each failing check, record the one-line remedy.
4. Emit both reports and set the exit code from `cooperative.usable`.

`doctor` is **detect-and-instruct by default**: it reports failures and their remedies but does not change machine state. Auto-remediation is opt-in via `--fix` ([[domain.uitool.injection]]): with `--fix`, `doctor` runs the remediable boot-arg / library-validation commands (the **unrestricted** posture's checks) under sudo, echoing each command before it runs, never running anything implicitly, and stopping at steps that require Recovery (SIP via `csrutil`) or a reboot — it sets what it can, then prints exactly which manual steps + reboot remain. The cooperative posture needs no machine state change, so `--fix` has nothing to apply there. Without `--fix`, machine state is never mutated.

The **target running**, **`get-task-allow`**, and **dyld-env** checks are part of the per-attach gate in [[domain.uitool.injection]] but are **not** evaluated by `doctor`, which takes no target argument; the output below lists exactly the machine-wide checks each posture needs. Those per-target checks are evaluated only by `attach` once a target is named.

## Output

A single JSON object on stdout: the two posture reports plus the OS build. Each `ModeReport` carries its own `usable` flag, its ordered `requires` array (one entry per check), and a one-line `note` saying what the posture is for. `pass` is true/false per check; `remedy` is present only on a failing check (one line, never a stack trace).

```jsonc
{
  "cooperative": {
    "usable": false,
    "requires": [
      { "check": "arch",             "pass": true,  "detail": "arm64e" },
      { "check": "injectable-arm64", "pass": false, "detail": "absent",
        "remedy": "build the arm64 UIToolBoot injectable (the injection half is not yet built)" }
    ],
    "note": "Inspect apps you build and sign for development (get-task-allow). No SIP / AMFI / library-validation changes — your machine is already capable."
  },
  "unrestricted": {
    "usable": false,
    "requires": [
      { "check": "sip",               "pass": true,  "detail": "disabled" },
      { "check": "amfi",              "pass": false, "detail": "enforcing",
        "remedy": "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot" },
      { "check": "libval",            "pass": true,  "detail": "disabled" },
      { "check": "arm64e-abi",        "pass": true,  "detail": "present" },
      { "check": "arch",              "pass": true,  "detail": "arm64e" },
      { "check": "injectable-arm64e", "pass": false, "detail": "absent",
        "remedy": "build the arm64e UIToolBoot injectable (the injection half is not yet built)" }
    ],
    "note": "Additionally required only to inspect apps you did NOT sign (system / notarized). Dedicated dev box; reversible from Recovery."
  },
  "osBuild": "26.3 (26D...)"
}
```

Output is deterministic: each `requires` array is emitted in a fixed order (as listed above), with stable key order and no addresses or timestamps. A posture's `usable` is true only when **every** check in its `requires` passes.

### The check sets per posture (pinned)

- **`cooperative.requires`** = `[ arch, injectable-arm64 ]`.
  - `arch` — the host is Apple Silicon (arm64e-capable).
  - `injectable-arm64` — the **arm64** `UIToolBoot` injectable is present (matches a normal Xcode arm64 app).
  - No `sip`, no `amfi`, no `libval`, no `arm64e-abi` — a stock SIP-enabled Mac is already capable for this posture.
- **`unrestricted.requires`** = `[ sip, amfi, libval, arm64e-abi, arch, injectable-arm64e ]`.
  - `sip` / `amfi` / `libval` / `arm64e-abi` — the machine-wide defang stack.
  - `arch` — the host is Apple Silicon (the **same** check the cooperative posture uses).
  - `injectable-arm64e` — the **arm64e** `UIToolBoot` injectable is present (matches the arm64e system frameworks / shared cache).

### Frozen check ids, detail tokens, and remedies

The per-check `check` ids and `detail` values are a **frozen, byte-stable contract** so the output can be asserted by **snapshot tests**. The per-check interpreters for `sip` / `amfi` / `libval` / `arm64e-abi` / `arch` and their tokens and remedies are **unchanged**; what changes is how they are **grouped** into the two postures and that the single `uitool-built` check is **split** into the posture-specific `injectable-arm64` (cooperative) and `injectable-arm64e` (unrestricted). `detail` is a fixed token per check, never free prose:

| check | posture(s) | `detail` when `pass` | `detail` when fail | remedy on fail |
| --- | --- | --- | --- | --- |
| `sip` | unrestricted | `disabled` | `enabled` | `boot to Recovery and run: csrutil enable --without kext --without dtrace; csrutil authenticated-root disable` |
| `amfi` | unrestricted | `disabled` | `enforcing` | `sudo nvram boot-args="amfi_get_out_of_my_way=0x1 -arm64e_preview_abi" && reboot` |
| `libval` | unrestricted | `disabled` | `enabled` | `sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool true` |
| `arm64e-abi` | unrestricted | `present` | `absent` | `sudo nvram boot-args="amfi_get_out_of_my_way=0x1 -arm64e_preview_abi" && reboot` |
| `arch` | both | `arm64e` | `arm64` \| `x86_64` (the reported arch) | `run uitool on an Apple Silicon (arm64e-capable) host` |
| `injectable-arm64` | cooperative | `present` | `absent` | `build the arm64 UIToolBoot injectable (the injection half is not yet built)` |
| `injectable-arm64e` | unrestricted | `present` | `absent` | `build the arm64e UIToolBoot injectable (the injection half is not yet built)` |

The `arch` check is **shared**: it appears in both `requires` arrays and reports the same verdict in each (an Apple Silicon host satisfies both postures; `x86_64` fails both). `detail` is the concrete reported arch, per the spec's "the built arch" failure token.

The top-level `osBuild` records the OS build (e.g. `26.3 (26D...)`) because precondition validity is OS-build-specific (arm64e injection regresses across Tahoe 26.x); it is **not a check**, never affects either posture's `usability`, and is normalized out of snapshot assertions (like a session id), not part of the byte-stable contract. `null` when it could not be read.

### Not ready today — and why

Today **neither posture is usable**, but for **different reasons**, and the report makes the distinction explicit:

- The **cooperative** posture fails today **only** on `injectable-arm64` — the arm64 `UIToolBoot` is not built yet. This is the **deferred injection half**, **not** a machine-defang gap. The machine itself needs **no** SIP / AMFI / library-validation change for the user's own apps; the report shows `arch` passing on any Apple Silicon Mac and only the (deferred) dylib missing.
- The **unrestricted** posture additionally fails on whichever of `sip` / `amfi` / `libval` / `arm64e-abi` are unmet on this machine, plus `injectable-arm64e`.

So the verdict is "not ready today," but `doctor` makes clear the cooperative path's only blocker is the deferred dylib, not anything the user must defang.

## States & exit codes

The exit code is driven by **`cooperative.usable`** — the cooperative posture is the common case, so it governs the control channel. Exit codes otherwise map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| `cooperative.usable` is true | 0 | both posture reports on stdout |
| `cooperative.usable` is false | 6 | both posture reports (with per-check remedies) on stdout; a one-line structured error on stderr ([[error.uitool.doctor-precondition-failed]]) |
| `--fix` remediated every remediable **unrestricted** check; only Recovery/reboot steps remain | 6 | both reports plus the remaining manual steps; the echoed commands and a one-line structured error on stderr — a reboot is still required, and `cooperative.usable` is unaffected by it |
| `--fix` ran and `cooperative.usable` is true | 0 | both reports on stdout (re-run after any reboot to confirm the unrestricted posture) |

**Today, `doctor` exits 6** — because `cooperative.usable` is false (the arm64 `UIToolBoot` is not built). The report explains that this gap is the **deferred injection half**, **not** a missing machine defang. Exit 6 is `PRECONDITION_FAILED` ([[domain.uitool.ipc]]); it stays precondition-only.

## Invariants

- Read-only and side-effect-free **by default**: inspects machine state, never mutates it unless `--fix` is passed ([[domain.uitool.injection]]).
- With `--fix`, mutation is explicit and visible: every command is echoed before it runs, nothing runs implicitly, Recovery/reboot steps are reported as remaining rather than performed, and only the **unrestricted** posture's remediable checks are touched.
- Reports **both** postures every run, so an agent always knows whether it needs the defang at all or just a cooperative target.
- The cooperative posture's `requires` never includes a machine-wide defang check — for the user's own apps the machine needs no SIP / AMFI / library-validation change.
- Does not open the IPC socket or contact any target process — it is the pre-injection gate, not a query.
- Each precondition is judged independently; no check is skipped because another failed ([[domain.uitool.injection]] invariant).
- Exit is 0 iff `cooperative.usable`; otherwise 6 (`PRECONDITION_FAILED`) — never exit 0 when the cooperative posture is not usable.
- Output is deterministic across runs on an unchanged machine.

## Notes

Cost tier: **cheap/bounded** — a fixed set of local reads (`csrutil status`, `nvram boot-args`, the LV plist, a `uname -m` arch read, two injectable-presence stats), no target process, no socket, no unbounded work.

The unrestricted posture's `arm64e-abi` and the `amfi`/`arm64e-abi` shared remedy command remain single points of failure tracked by [[domain.uitool.injection]] — `-arm64e_preview_abi` is removable by Apple in any point release, and arm64e injection is actively regressing on Tahoe 26.x. None of that touches the cooperative posture, which depends on neither boot-arg.
