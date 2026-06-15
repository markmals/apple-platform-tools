---
id: story.uitool.signing-read
kind: story
depends-on: [domain.uitool.injection, domain.uitool.ipc]
---

# Read a target's injection posture from its signature

**As a** coding agent deciding whether to inspect an app
**I want** to read the target's code signature and a plain injectability verdict
**So that** I know the injection posture before I attach, not after a failed try.

**Independent test:** Run `uitool signing` against a debug-signed get-task-allow
app; observe `signed: true`, `getTaskAllow: true`, and `cooperativeInjectable:
true`, with no injection.

## Acceptance Criteria

### Scenario 1: Read a get-task-allow target as cooperatively injectable

<!-- id: scenario.uitool.signing-read.cooperative -->

- Given a debug-signed app carrying `get-task-allow` and no hardened runtime
- When the agent runs `uitool signing` against it
- Then the report shows `signed: true`, `getTaskAllow: true`, and `cooperativeInjectable: true`
- And no injection or attach occurred

### Scenario 2: A target without get-task-allow is not cooperatively injectable

<!-- id: scenario.uitool.signing-read.not-cooperative -->

- Given a target that does not carry `get-task-allow`
- When the agent runs `uitool signing` against it
- Then `getTaskAllow` is false and `cooperativeInjectable` is false ([[domain.uitool.injection]] — it needs the unrestricted posture)

### Scenario 3: A target that cannot be resolved fails distinctly

<!-- id: scenario.uitool.signing-read.not-found -->

- Given a bundle id or path that resolves to no binary
- When the agent runs `uitool signing` against it
- Then it fails with exit code 3 and a structured error

### Scenario 4: The report is deterministic

<!-- id: scenario.uitool.signing-read.deterministic -->

- When the agent reads the same unchanged target twice
- Then the two reports are byte-identical
