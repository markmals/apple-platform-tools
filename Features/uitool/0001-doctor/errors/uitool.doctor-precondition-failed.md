---
id: error.uitool.doctor-precondition-failed
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.doctor]
---

# Precondition failed

## When this happens

The agent runs [[command.uitool.doctor]] (or any command that gates on the precondition stack) and the **cooperative** posture is not usable — i.e. `cooperative.usable` is false, because one of its required checks (`arch`, `injectable-arm64`) is unmet. The exit code tracks the cooperative posture only; an unusable **unrestricted** posture alone does not raise this error if the cooperative one is usable. This is the failure that, without `doctor`, would otherwise surface much later as a silent "dylib didn't load".

## What the user sees

Both posture reports on stdout, each naming its failed checks and, for each, a single concrete remedy. The command exits 6 ([[domain.uitool.ipc]]). A one-line structured error is also printed to stderr, carrying the wire code `PRECONDITION_FAILED`.

> "Precondition failed: cooperative — injectable-arm64 absent. Remedy: build the arm64 UIToolBoot injectable (the injection half is not yet built)."

## What this is NOT — the cooperative posture needs no machine defang

This error does **not** mean the machine must be SIP-disabled, AMFI-loosened, or library-validation-overridden to inspect the user's **own** apps. macOS gates injection per target: an app the user builds and signs for development carries `get-task-allow`, which is honored on a **stock, SIP-enabled Mac**. The cooperative posture's only machine requirements are an Apple Silicon host and the **arm64** `UIToolBoot` injectable.

So **today** this error is raised because the arm64 `UIToolBoot` injectable is not built yet — the **deferred injection half** — **not** because the machine is missing a defang. The full SIP/AMFI/LV/arm64e-ABI defang stack is required **only** for the **unrestricted** posture (inspecting apps the user did NOT sign — system / notarized), and an unusable unrestricted posture is reported in its own `ModeReport` without, by itself, setting exit 6.

## What the user can do

- **Read both `ModeReport`s** — `cooperative` tells you what's needed to inspect your own apps (today: just the deferred arm64 dylib); `unrestricted` tells you the additional defang needed only for apps you did not sign.
- **Apply the named remedy(ies)** — each failed check carries its own one-line fix. The cooperative posture's failures (today, the absent arm64 injectable) need no reboot; the unrestricted posture's boot-arg and SIP changes each require a reboot afterward.
- **Re-run `doctor`** — confirm `cooperative.usable` is now true (exit 0) before attempting cooperative attachment.
- **Branch on exit code 6** — the agent detects a cooperative-precondition failure without parsing prose ([[domain.uitool.ipc]]).

## Underlying cause (informational)

- **Cooperative posture (governs the exit code):** the host is not Apple Silicon, or the **arm64** `UIToolBoot` injectable is built as some other slice or absent. Today the latter holds — the arm64 injectable is part of the deferred injection half.
- **Unrestricted posture (reported, but only the cooperative posture sets exit 6):** SIP not lowered to Permissive Security; missing `amfi_get_out_of_my_way=0x1` or `-arm64e_preview_abi` in `boot-args`; `DisableLibraryValidation` unset; the **arm64e** `UIToolBoot` injectable absent or built as plain-arm64.
- Any single unmet link within a posture marks that posture not-usable; [[command.uitool.doctor]] reports all of them independently so a half-configured machine is fully diagnosed in one run.

## Related

- [[command.uitool.doctor]] — the command that emits this error and the two-posture report.
- [[domain.uitool.injection]] — the precondition stack and its remedies.
- [[domain.uitool.ipc]] — exit-code 6 mapping and the `PRECONDITION_FAILED` wire code.
- [[story.uitool.doctor-preconditions]] — the capability this protects.
