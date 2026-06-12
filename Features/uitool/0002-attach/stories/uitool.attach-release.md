---
id: story.uitool.attach-release
kind: story
depends-on: [domain.uitool.injection, domain.uitool.ipc]
---

# Release an inspected app

**As a** coding agent reverse-engineering a macOS app
**I want** to end an inspection session for a target app
**So that** the app runs normally again and I free the resources I was holding.

**Independent test:** Attach to the harness app, then detach; observe success (exit 0); then issue any read query and observe it fails as not-attached rather than reaching the app.

## Acceptance Criteria

### Scenario 1: Detach an attached target

<!-- id: scenario.uitool.attach-release.detach -->

- Given a target app the agent has attached to
- When the agent detaches from the target
- Then the detach succeeds with exit code 0 ([[domain.uitool.ipc]])
- And the result reports the per-target channel as closed
- And a subsequent read query to the same target fails as not-attached (exit code 4)

### Scenario 2: Detaching a target that is not attached is idempotent

<!-- id: scenario.uitool.attach-release.idempotent -->

- Given a target app the agent has not attached to (or has already detached)
- When the agent detaches from the target
- Then the detach succeeds with exit code 0
- And the result reports the per-target channel as closed

### Scenario 3: Detaching a running-attached target does not terminate it

<!-- id: scenario.uitool.attach-release.app-survives -->

- Given a target app the agent attached to via the running-process path (Path B)
- When the agent detaches from the target
- Then the target app is still running

### Scenario 4: Lifecycle of a relaunch-injected target after detach

<!-- id: scenario.uitool.attach-release.app-survives-relaunched -->

- Given a target app the agent attached to via the relaunch path (Path A)
- When the agent detaches from the target
- Then the relaunched process is still running — detach removes only the inspection bridge and never terminates the target
- And its lifecycle thereafter is the researcher's concern, not the tool's (the tool that relaunched it does not adopt ownership; defined by the injection half where Path A is built)
