---
id: error.uitool.attach-precondition
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Injection precondition failed

## When this happens

The agent attaches or launches, but a link in the injection precondition stack ([[domain.uitool.injection]]) is not satisfied. **Which links apply depends on the posture:** the **cooperative** path (your own `get-task-allow` app) needs only an Apple Silicon host and the matching arm64 [[domain.uitool.boot]] dylib (plus, for attach-to-running, `uitool` being debugger-entitled and the target being same-user) — **no SIP/AMFI/libval changes**; the **unrestricted** path (a target you did not sign) additionally needs the full machine defang — SIP off, AMFI boot-arg, library validation off, the arm64e ABI, and the arm64e dylib. Any one failing would otherwise produce a silent "dylib didn't load", so the command refuses up front rather than proceeding.

## What the user sees

Exit code 6 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr that names **exactly which** precondition failed plus a one-line remediation ([[domain.uitool.injection]] invariant) — never a stack trace.

> `{"ok":false,"error":{"code":"PRECONDITION_FAILED","message":"AMFI not disabled","recover":"add amfi_get_out_of_my_way=0x1 to nvram boot-args and reboot; then re-run uitool doctor"}}`

The wire `error.code` is a single canonical `PRECONDITION_FAILED` (exit 6); the failing check is named in `message`, satisfying [[domain.uitool.injection]]'s requirement to report "exactly which failed plus a one-line remedy" without a per-link code explosion.

## What the user can do

- Apply the named remediation (cooperative: build the arm64 [[domain.uitool.boot]] dylib; unrestricted: set the boot-arg, disable library validation, build the arm64e dylib), reboot if required, then re-attach or re-launch.
- Run `uitool doctor` for the full precondition verdict across all links at once.
- Run `uitool doctor --fix` to opt into auto-remediation ([[domain.uitool.injection]] invariant): it echoes each command before running it, never runs implicitly, and sets what it can — then prints exactly which manual steps (SIP via Recovery `csrutil`) and reboot remain.

## Underlying cause (informational)

- A cooperative check failed: not an Apple Silicon host, or the **arm64** [[domain.uitool.boot]] dylib absent (and, for attach-to-running, `uitool` not debugger-entitled or the target not same-user / not `get-task-allow`).
- Or an unrestricted check failed: SIP enabled, AMFI not disabled, library validation enabled, missing `-arm64e_preview_abi`, or the **arm64e** boot dylib absent.

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[error.uitool.attach-injection-failed]] — distinct: preconditions passed but injection still did not take (exit 4).
- `uitool doctor` / `uitool doctor --fix` — the dedicated precondition-verdict command and its explicit auto-remediation flag (a separate feature; [[domain.uitool.injection]] invariant).
