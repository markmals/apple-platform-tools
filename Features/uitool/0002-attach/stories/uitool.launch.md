---
id: story.uitool.launch
kind: story
depends-on: [domain.uitool.injection, domain.uitool.boot, domain.uitool.server, domain.uitool.ipc, domain.uitool.node-id]
---

# Launch an app under inspection

**As a** coding agent reverse-engineering a macOS app
**I want** to start a target app fresh with the inspector already loaded
**So that** I can inspect it from a known clean state without first getting an
inspection bridge into a running process.

**Independent test:** With the harness app not running, launch it; observe success
(exit 0) and a result reporting the launch path, an open channel, and a session
marker; then issue any read query and observe it reaches the launched app rather
than failing as not-attached.

## Acceptance Criteria

### Background

- Given the cooperative launch preconditions are satisfied — an Apple Silicon host and the arm64 boot dylib present ([[domain.uitool.injection]])

### Scenario 1: Launch a cold app under inspection

<!-- id: scenario.uitool.launch.cold -->

- Given the target app is not currently running
- When the agent launches the target
- Then the launch succeeds with exit code 0 ([[domain.uitool.ipc]])
- And the result reports the attach path taken as launch
- And the result reports the per-target channel as open
- And the result carries a session marker ([[domain.uitool.node-id]])

### Scenario 2: Launched app receives passthrough arguments

<!-- id: scenario.uitool.launch.app-args -->

- Given the target app is not currently running
- When the agent launches the target with arguments after `--`
- Then the launch succeeds with exit code 0
- And the launched process receives those arguments

### Scenario 3: Launching an already-running target refuses without `--replace`

<!-- id: scenario.uitool.launch.already-running -->

- Given a same-user instance of the target is already running
- When the agent launches the target without `--replace`
- Then the launch fails with exit code 2 ([[domain.uitool.ipc]])
- And a structured error directs the agent to attach (to inspect it preserving state) or to re-run with `--replace`
- And the running instance is left untouched — it is never silently terminated

### Scenario 4: `--replace` terminates the running instance and launches fresh

<!-- id: scenario.uitool.launch.replace -->

- Given a same-user instance of the target is already running
- When the agent launches the target with `--replace`
- Then the prior instance is terminated and a fresh instance is launched under inspection
- And the launch succeeds with exit code 0
- And the result reports that a prior instance was replaced
- And the session marker is a fresh epoch, not the prior session's ([[domain.uitool.node-id]])

### Scenario 5: Launching an app that cannot be found fails distinctly

<!-- id: scenario.uitool.launch.not-found -->

- Given no launchable app resolves for the requested bundle id or path
- When the agent launches the target
- Then the launch fails with exit code 3 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint ([[error.uitool.launch-not-found]])

### Scenario 6: Injection that does not take is reported, never silently accepted

<!-- id: scenario.uitool.launch.injection-failed -->

- Given the target is spawned but the inspector channel never opens within the bounded wait
- When the agent launches the target
- Then the launch fails with exit code 4 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint ([[error.uitool.attach-injection-failed]])
- And the agent is never told the launch succeeded

### Scenario 7: A failed launch precondition refuses up front

<!-- id: scenario.uitool.launch.precondition-failed -->

- Given a link in the cooperative launch precondition stack is not satisfied ([[domain.uitool.injection]])
- When the agent launches the target
- Then the launch fails with exit code 6 ([[domain.uitool.ipc]])
- And a structured error names exactly which precondition failed plus a one-line remediation ([[error.uitool.attach-precondition]])
- And the agent is never told the launch succeeded

### Scenario 8: A handshake the launched app never answers times out

<!-- id: scenario.uitool.launch.handshake-timeout -->

- Given the target launches and the channel opens but its main thread is busy when the handshake marshals work to it
- When the agent launches the target and the channel opens
- Then the launch fails with exit code 7 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint ([[error.uitool.attach-timeout]])
- And the agent is never told the launch succeeded

### Scenario 9: A schema-version mismatch is reported, never silently accepted

<!-- id: scenario.uitool.launch.schema-mismatch -->

- Given the target launches and the handshake completes but the injected server reports a protocol/schema version the CLI does not expect ([[domain.uitool.ipc]])
- When the agent launches the target
- Then the launch fails with exit code 8 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint ([[error.uitool.attach-schema-mismatch]])
- And the agent is never told the launch succeeded
