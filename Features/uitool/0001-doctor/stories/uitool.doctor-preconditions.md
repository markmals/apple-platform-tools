---
id: story.uitool.doctor-preconditions
kind: story
depends-on: [domain.uitool.injection, domain.uitool.ipc]
---

# Verify the injection preconditions

**As a** coding agent inspecting a macOS app's runtime UI
**I want** a verdict on each injection precondition independently, with a one-line remedy for any that fail
**So that** a misconfigured machine gives me a clean, itemized failure I can act on instead of a silent "dylib didn't load" later.

# Acceptance Criteria

## Background

- Given no target app is involved and no attachment is performed
- And the machine is in a known precondition state

## Scenario 1: Fully configured machine reports all checks passing

<!-- id: scenario.uitool.doctor-preconditions.all-pass -->

- Given a dev machine where SIP is disabled, the AMFI and arm64e-ABI boot-args are set, library validation is disabled, and the arm64e `UIToolBoot` injectable is built
- When the agent verifies the preconditions
- Then the result reports every precondition check as passing
- And the command exits 0

## Scenario 2: One failed precondition is named with a remedy

<!-- id: scenario.uitool.doctor-preconditions.one-fail -->

- Given a dev machine where exactly one precondition is unmet
- When the agent verifies the preconditions
- Then the result identifies that specific check as failed
- And the result includes a one-line remedy for that check
- And every other check is reported as passing
- And the command exits 6 (precondition failed — see [[domain.uitool.ipc]])

## Scenario 3: Several failed preconditions are each reported

<!-- id: scenario.uitool.doctor-preconditions.multi-fail -->

- Given a dev machine where more than one precondition is unmet
- When the agent verifies the preconditions
- Then the result reports each unmet precondition individually with its own remedy
- And the command exits 6 (precondition failed — see [[domain.uitool.ipc]])

## Scenario 4: Each precondition is judged independently

<!-- id: scenario.uitool.doctor-preconditions.independent -->

- Given a dev machine where SIP is disabled but the AMFI boot-arg is missing
- When the agent verifies the preconditions
- Then the SIP check is reported as passing
- And the AMFI check is reported as failing
- And no check's verdict is suppressed or skipped because another check failed

## Scenario 5: Detection never mutates machine state by default

<!-- id: scenario.uitool.doctor-preconditions.detect-only -->

- Given a dev machine with one or more unmet preconditions
- When the agent verifies the preconditions without the `--fix` flag
- Then the failed checks are reported with their remedies
- And no boot-arg, library-validation, or SIP setting is changed
- And the command exits 6 (precondition failed — see [[domain.uitool.ipc]])

## Scenario 6: --fix opts into remediation and stops at Recovery/reboot

<!-- id: scenario.uitool.doctor-preconditions.fix -->

- Given a dev machine where a remediable precondition (a boot-arg or library validation) is unmet
- And SIP must still be lowered via Recovery
- When the agent verifies the preconditions with the `--fix` flag
- Then each remediation command is echoed before it runs
- And the remediable precondition is applied under sudo
- And the SIP/Recovery and reboot steps are reported as remaining rather than performed
- And the command exits 6 (a reboot is still required, so this is not yet all-pass — see [[domain.uitool.ipc]])
