---
id: error.uitool.doctor-precondition-failed
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.doctor]
---

# Precondition failed

## When this happens

The agent runs [[command.uitool.doctor]] (or any command that gates on the precondition stack) and one or more checks in [[domain.uitool.injection]]'s precondition stack is unmet. This is the failure that, without `doctor`, would otherwise surface much later as a silent "dylib didn't load".

## What the user sees

A verdict naming each failed check and, for each, a single concrete remedy. The command exits 6 ([[domain.uitool.ipc]]). A one-line structured error is also printed to stderr, carrying the wire code `PRECONDITION_FAILED`.

> "Precondition failed: amfi — amfi_get_out_of_my_way not set. Remedy: sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot."

## What the user can do

- **Apply the named remedy(ies)** — each failed check carries its own one-line fix; for boot-arg and SIP changes a reboot is required afterward.
- **Re-run `doctor`** — confirm the verdict is now all-pass (exit 0) before attempting attachment.
- **Branch on exit code 6** — the agent can detect a precondition failure without parsing prose ([[domain.uitool.ipc]]).

## Underlying cause (informational)

- SIP not lowered to Permissive Security; missing `amfi_get_out_of_my_way=0x1` or `-arm64e_preview_abi` in `boot-args`; `DisableLibraryValidation` unset; the arm64e `UIToolBoot` injectable built as plain-arm64 (not arm64e) or absent.
- Any single unmet link produces this error; [[command.uitool.doctor]] reports all of them independently so a half-configured machine is fully diagnosed in one run.

## Related

- [[command.uitool.doctor]] — the command that emits this error.
- [[domain.uitool.injection]] — the precondition stack and its remedies.
- [[domain.uitool.ipc]] — exit-code 6 mapping and the `PRECONDITION_FAILED` wire code.
- [[story.uitool.doctor-preconditions]] — the capability this protects.
