---
id: error.uitool.attach-precondition
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.attach]
---

# Injection precondition failed

## When this happens

The agent attaches, but a link in the injection precondition stack ([[domain.uitool.injection]]) is not satisfied — SIP, AMFI, library validation, the arm64e ABI, arch match, or FLEX-mac being built. Any one failing would otherwise produce a silent "dylib didn't load", so `attach` refuses up front rather than proceeding.

## What the user sees

Exit code 6 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr that names **exactly which** precondition failed plus a one-line remediation ([[domain.uitool.injection]] invariant) — never a stack trace.

> `{"ok":false,"error":{"code":"PRECONDITION_FAILED","message":"AMFI not disabled","recover":"add amfi_get_out_of_my_way=0x1 to nvram boot-args and reboot; then re-run uitool doctor"}}`

The wire `error.code` is a single canonical `PRECONDITION_FAILED` (exit 6); the failing check is named in `message`, satisfying [[domain.uitool.injection]]'s requirement to report "exactly which failed plus a one-line remedy" without a per-link code explosion.

## What the user can do

- Apply the named remediation (e.g. set the boot-arg, disable library validation, build FLEX-mac arm64e), reboot if required, then re-attach.
- Run `uitool doctor` for the full precondition verdict across all links at once.
- Run `uitool doctor --fix` to opt into auto-remediation ([[domain.uitool.injection]] invariant): it echoes each command before running it, never runs implicitly, and sets what it can — then prints exactly which manual steps (SIP via Recovery `csrutil`) and reboot remain.

## Underlying cause (informational)

- One of the [[domain.uitool.injection]] checks failed: SIP enabled, AMFI not disabled, library validation enabled, missing `-arm64e_preview_abi`, the dylib not built arm64e, or `FLEXMac.framework` absent.

## Related

- [[command.uitool.attach]] — the verb that surfaces this.
- [[error.uitool.attach-injection-failed]] — distinct: preconditions passed but injection still did not take (exit 4).
- `uitool doctor` / `uitool doctor --fix` — the dedicated precondition-verdict command and its explicit auto-remediation flag (a separate feature; [[domain.uitool.injection]] invariant).
