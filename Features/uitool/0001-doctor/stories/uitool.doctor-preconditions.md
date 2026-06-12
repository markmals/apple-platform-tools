---
id: story.uitool.doctor-preconditions
depends-on: [domain.uitool.injection, domain.uitool.ipc]
kind: story
---

# Verify the injection preconditions

**As a** coding agent inspecting a macOS app's runtime UI
**I want** a verdict on what I can attach to from this machine — split into the **cooperative** posture (my own get-task-allow apps) and the **unrestricted** posture (any app, incl. system) — with a one-line remedy for any unmet check
**So that** I learn the common case (inspecting my own app) needs no machine defanging, and a misconfigured machine gives me a clean, itemized failure I can act on instead of a silent "dylib didn't load" later.

# Acceptance Criteria

## Background

- Given no target app is involved and no attachment is performed
- And the machine is in a known precondition state
- And `doctor` reports two postures — `cooperative` and `unrestricted` — each with its own `requires` checks and `usable` verdict
- And the command's exit code follows the **cooperative** posture: 0 when `cooperative.usable`, else 6 ([[domain.uitool.ipc]])

## Scenario 1: A stock SIP-enabled Mac is cooperative-ready

<!-- id: scenario.uitool.doctor-preconditions.cooperative-ready -->

- Given a stock dev Mac with SIP enabled, no boot-args set, and a normal arm64 build — but the **arm64** `UIToolBoot` injectable built
- When the agent verifies the preconditions
- Then `cooperative.usable` is true — inspecting apps you build and sign for development (get-task-allow) needs no SIP / AMFI / library-validation change
- And the `cooperative.requires` set contains no `sip`, `amfi`, or `libval` check
- And `unrestricted.usable` is false — the system-wide defang is absent
- And the command exits 0

## Scenario 2: The injection half being unbuilt blocks cooperative only on the dylib

<!-- id: scenario.uitool.doctor-preconditions.injection-half-pending -->

- Given a stock dev Mac with neither `UIToolBoot` injectable built (today's state — the injection half is deferred)
- When the agent verifies the preconditions
- Then `cooperative.usable` is false, and its **only** failing check is `injectable-arm64` with a remedy — no `sip`/`amfi`/`libval` item is even present to fail
- And the command exits 6, because the gap is the deferred dylib, not a missing machine defang

## Scenario 3: A fully defanged machine makes both postures usable

<!-- id: scenario.uitool.doctor-preconditions.all-pass -->

- Given a dev box where SIP is disabled, the AMFI and arm64e-ABI boot-args are set, library validation is disabled, the host is arm64e, and **both** the arm64 and arm64e `UIToolBoot` injectables are built
- When the agent verifies the preconditions
- Then `cooperative.usable` and `unrestricted.usable` are both true, every check passing
- And the command exits 0

## Scenario 4: SIP enabled fails the unrestricted posture but leaves cooperative usable

<!-- id: scenario.uitool.doctor-preconditions.one-fail -->

- Given a machine with both injectables built but SIP enabled
- When the agent verifies the preconditions
- Then the `unrestricted` posture reports its `sip` check failed with a one-line remedy, and is not usable
- And the `cooperative` posture remains usable (it never reads SIP)
- And the command exits 0 — the common case still works

## Scenario 5: Several unmet unrestricted preconditions are each reported

<!-- id: scenario.uitool.doctor-preconditions.multi-fail -->

- Given a machine where more than one unrestricted precondition is unmet (e.g. SIP enabled, no boot-args, x86_64, no injectable)
- When the agent verifies the preconditions
- Then the `unrestricted` posture reports each unmet precondition individually with its own remedy
- And the command exits 6 (the cooperative posture is also unusable here)

## Scenario 6: Each unrestricted precondition is judged independently

<!-- id: scenario.uitool.doctor-preconditions.independent -->

- Given a machine where SIP is disabled but the AMFI boot-arg is missing
- When the agent verifies the preconditions
- Then the `sip` check is reported as passing
- And the `amfi` check is reported as failing
- And no check's verdict is suppressed or skipped because another check failed

## Scenario 7: Detection never mutates machine state by default

<!-- id: scenario.uitool.doctor-preconditions.detect-only -->

- Given a machine with one or more unmet preconditions
- When the agent verifies the preconditions without the `--fix` flag
- Then the failed checks are reported with their remedies
- And no boot-arg, library-validation, or SIP setting is changed

## Scenario 8: --fix opts into remediation of the unrestricted stack and stops at Recovery/reboot

<!-- id: scenario.uitool.doctor-preconditions.fix -->

- Given a dev box where a remediable **unrestricted** precondition (a boot-arg or library validation) is unmet
- And SIP must still be lowered via Recovery
- When the agent verifies the preconditions with the `--fix` flag
- Then each remediation command is echoed before it runs
- And the remediable precondition is applied under sudo
- And the SIP/Recovery and reboot steps are reported as remaining rather than performed
- And the command still exits 6 (a reboot is required; `--fix` is part of the deferred injection half)
