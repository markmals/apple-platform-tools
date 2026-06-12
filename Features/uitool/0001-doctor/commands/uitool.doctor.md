---
id: command.uitool.doctor
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, story.uitool.doctor-preconditions]
---

# `uitool doctor` — verify the injection precondition stack

## Synopsis

```
uitool doctor [--fix]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| (none) | — | — | `doctor` takes no target; it inspects only the local machine. |
| `--fix` | flag | no | Opt into sudo auto-remediation of the remediable checks ([[domain.uitool.injection]]). Off by default — `doctor` detects and instructs unless `--fix` is passed. Echoes each command before running it, never runs anything implicitly, and stops at steps that need Recovery (SIP via `csrutil`) or a reboot, printing exactly which manual steps remain. |

There is no `--json` flag: JSON is the only output. The consumer is a coding agent, not a human at a TTY, so output is always deterministic JSON on stdout ([[architecture]]) — there is no human-readable mode to toggle.

## Behavior

`doctor` is **pure local detection** — it runs before any injection and does **not** open the IPC socket or contact a target ([[domain.uitool.ipc]] describes the post-injection wire protocol, which this command does not use). It inspects the **machine-wide** subset of the precondition stack defined in [[domain.uitool.injection]], judging **each check independently** so a half-configured machine yields an itemized verdict rather than a single mystery failure:

1. Evaluate each machine-wide precondition in [[domain.uitool.injection]]'s stack independently — every check in the stack except `target running`, which requires a named target `doctor` does not take.
2. For each check, record pass/fail and, on fail, the one-line remedy.
3. Emit the verdict and set the exit code from the aggregate result.

`doctor` is **detect-and-instruct by default**: it reports failures and their remedies but does not change machine state. Auto-remediation is opt-in via `--fix` ([[domain.uitool.injection]]): with `--fix`, `doctor` runs the remediable boot-arg / library-validation commands under sudo, echoing each command before it runs, never running anything implicitly, and stopping at steps that require Recovery (SIP via `csrutil`) or a reboot — it sets what it can, then prints exactly which manual steps + reboot remain. Without `--fix`, machine state is never mutated.

The **target running** check is part of the stack in [[domain.uitool.injection]] but is **not** evaluated by `doctor`, which takes no target argument; the output example below lists exactly the machine-wide checks. `target running` is evaluated only by `attach` / `sip-preflight` once a target is named — `doctor` does not accept an optional target to fold that check in.

## Output

A single JSON object on stdout: an overall verdict plus one entry per check. `pass` is true/false; `remedy` is present only on failure (one line, never a stack trace).

```jsonc
{
  "ok": false,
  "osBuild": "26.3 (26D...)",
  "checks": [
    { "check": "sip",          "pass": true,  "detail": "disabled" },
    { "check": "amfi",         "pass": false, "detail": "enforcing",
      "remedy": "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot" },
    { "check": "libval",       "pass": true,  "detail": "disabled" },
    { "check": "arm64e-abi",   "pass": true,  "detail": "present" },
    { "check": "arch",         "pass": true,  "detail": "arm64e" },
    { "check": "uitool-built", "pass": true,  "detail": "present" }
  ]
}
```

Output is deterministic: the checks array is emitted in a fixed order (as listed above), with stable key order and no addresses or timestamps. `ok` is true only when every check passes.

The `check` ids and `detail` values are a **frozen, byte-stable contract** so the output can be asserted by **snapshot tests**. The six check ids are exactly `sip`, `amfi`, `libval`, `arm64e-abi`, `arch`, `uitool-built`, always in that order. `detail` is a fixed token per check, never free prose:

| check | `detail` when `pass` | `detail` when fail |
| --- | --- | --- |
| `sip` | `disabled` | `enabled` |
| `amfi` | `disabled` | `enforcing` |
| `libval` | `disabled` | `enabled` |
| `arm64e-abi` | `present` | `absent` |
| `arch` | `arm64e` | `arm64` \| `x86_64` (the built arch) |
| `uitool-built` | `present` | `absent` |

`remedy` (present only on a failing check) is the exact one-line command to run. The top-level `osBuild` records the OS build (e.g. `26.3 (26D...)`) because precondition validity is OS-build-specific (arm64e injection regresses across Tahoe 26.x); it is machine-specific and is normalized out of snapshot assertions (like a session id), not part of the byte-stable contract.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| all checks pass | 0 | the verdict object on stdout |
| one or more preconditions failed | 6 | the verdict object (with per-check remedies); a one-line structured error on stderr (see [[error.uitool.doctor-precondition-failed]]) |
| `--fix` remediated every remediable check; only Recovery/reboot steps remain | 6 | the verdict object plus the remaining manual steps; the echoed commands and a one-line structured error on stderr — a reboot is still required, so this is not yet all-pass |
| `--fix` remediated every check and none required Recovery/reboot | 0 | the verdict object on stdout (re-run after any reboot to confirm) |

## Invariants

- Read-only and side-effect-free **by default**: inspects machine state, never mutates it unless `--fix` is passed ([[domain.uitool.injection]]).
- With `--fix`, mutation is explicit and visible: every command is echoed before it runs, nothing runs implicitly, and Recovery/reboot steps are reported as remaining rather than performed.
- Does not open the IPC socket or contact any target process — it is the pre-injection gate, not a query.
- Each precondition is judged independently; no check is skipped because another failed ([[domain.uitool.injection]] invariant).
- Never exits 0 on a failed precondition; an aggregate failure is always exit 6.
- Output is deterministic across runs on an unchanged machine.

## Notes

Cost tier: **cheap/bounded** — a fixed set of local reads (`csrutil status`, `nvram boot-args`, the LV plist, a `file`/`lipo` arch read, a framework-presence stat), no target process, no socket, no unbounded work.
