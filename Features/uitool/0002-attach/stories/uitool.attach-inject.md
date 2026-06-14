---
id: story.uitool.attach-inject
kind: story
depends-on: [domain.uitool.injection, domain.uitool.ipc, domain.uitool.node-id]
---

# Make a running app inspectable

**As a** coding agent reverse-engineering a macOS app
**I want** to make a target app inspectable in one step
**So that** my later queries about its view tree have something to talk to.

**Independent test:** Start the harness app, attach to it, observe success (exit 0) and a result naming the open channel and a session marker; then issue any read query and observe it reaches the app rather than failing as not-attached.

## Acceptance Criteria

### Background

- Given the environment preconditions for injection are satisfied ([[domain.uitool.injection]])

### Scenario 1: Attach to the running process, preserving its state

<!-- id: scenario.uitool.attach-inject.running -->

- Given a target app that is running with on-screen state worth preserving
- When the agent attaches to the target
- Then the attach succeeds with exit code 0 ([[domain.uitool.ipc]])
- And the result reports the attach path taken as running
- And the result reports the per-target channel as open
- And the result carries a session marker distinct from any prior session ([[domain.uitool.node-id]])
- And the result does not claim to confirm the app's pre-attach UI state was preserved — state preservation is the attach-to-running path's purpose but is not externally observable from the command's output, so no result field asserts it

> Relaunching a target for a clean-launch state is [[command.uitool.launch]]'s job
> ([[story.uitool.launch]] scenario.uitool.launch.cold / .replace), not a flag on
> attach — `attach` is attach-to-running only.

### Scenario 2: Attaching an already-attached target is idempotent

<!-- id: scenario.uitool.attach-inject.idempotent -->

- Given a target app that the agent has already attached to in this session
- When the agent attaches to the same target again
- Then the attach succeeds with exit code 0
- And the result reports the per-target channel as open
- And the session marker is unchanged from the first attach ([[domain.uitool.injection]] lifecycle: a second attach reuses the existing server)

### Scenario 3: Each fresh attach starts a new session

<!-- id: scenario.uitool.attach-inject.new-epoch -->

- Given a target app that was attached and then detached
- When the agent attaches to the target again
- Then the attach succeeds with exit code 0
- And the session marker differs from the previous session's marker ([[domain.uitool.node-id]] epoch is bumped on attach)

### Scenario 4: Attaching a target that is not running fails distinctly

<!-- id: scenario.uitool.attach-inject.not-running -->

- Given no process exists for the requested target
- When the agent attaches to the target
- Then the attach fails with exit code 3 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint

### Scenario 5: Injection that does not take is reported, never silently accepted

<!-- id: scenario.uitool.attach-inject.injection-failed -->

- Given a target app that is running but cannot be injected (the injected channel never opens within the bounded wait)
- When the agent attaches to the target
- Then the attach fails with exit code 4 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint
- And the agent is never told the attach succeeded

### Scenario 6: A failed injection precondition refuses up front

<!-- id: scenario.uitool.attach-inject.precondition-failed -->

- Given a target app that is running but a link in the injection precondition stack is not satisfied ([[domain.uitool.injection]])
- When the agent attaches to the target
- Then the attach fails with exit code 6 ([[domain.uitool.ipc]])
- And a structured error names exactly which precondition failed plus a one-line remediation ([[error.uitool.attach-precondition]])
- And the agent is never told the attach succeeded

### Scenario 7: A handshake that the target never answers times out

<!-- id: scenario.uitool.attach-inject.handshake-timeout -->

- Given a target app that is running and injectable but whose main thread is busy when the handshake marshals work to it
- When the agent attaches to the target and the channel opens
- Then the attach fails with exit code 7 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint ([[error.uitool.attach-timeout]])
- And the agent is never told the attach succeeded

### Scenario 8: A schema-version mismatch is reported, never silently accepted

<!-- id: scenario.uitool.attach-inject.schema-mismatch -->

- Given a target app that is running and injectable but whose injected server reports a protocol/schema version the CLI does not expect ([[domain.uitool.ipc]])
- When the agent attaches to the target and the handshake completes
- Then the attach fails with exit code 8 ([[domain.uitool.ipc]])
- And a structured error names the cause and a recovery hint ([[error.uitool.attach-schema-mismatch]])
- And the agent is never told the attach succeeded
