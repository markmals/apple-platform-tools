---
id: story.uitool.windows-enumerate
kind: story
depends-on: [domain.uitool.node, domain.uitool.ipc, domain.uitool.node-id]
---

# Enumerate top-level windows

**As a** coding agent
**I want** to list the target app's top-level windows with their handles, titles, frames, and focus status
**So that** I can pick which window to investigate without downloading any view tree.

## Acceptance Criteria

### Background

- Given the agent has attached to a running target app

### Scenario 1: Listing the open windows

<!-- id: scenario.uitool.windows-enumerate.happy-path -->

- Given the target app has two top-level windows open
- When the agent requests the list of top-level windows
- Then they receive one record per top-level window
    - And each record carries a node id, a title, a frame, and key/main flags
- And the process exits 0

### Scenario 2: Identifying the focused window

<!-- id: scenario.uitool.windows-enumerate.key-window -->

- Given the target app is frontmost with one window receiving keyboard input
- When the agent requests the list of top-level windows
- Then exactly one record is flagged as the key window
- And exactly one record is flagged as the main window
- And the process exits 0

### Scenario 3: An app with no open windows

<!-- id: scenario.uitool.windows-enumerate.empty -->

- Given the target app is running but has no top-level windows open
- When the agent requests the list of top-level windows
- Then they receive an empty list carrying `_meta.totalMatched: 0`, distinct from a failure
- And the process exits 0

### Scenario 4: First listing of an unchanged app

<!-- id: scenario.uitool.windows-enumerate.baseline -->

- Given the target app's windows have not changed since attach
- When the agent requests the list of top-level windows
- Then they receive a record per top-level window in a deterministic order

### Scenario 5: Repeat listing of an unchanged app

<!-- id: scenario.uitool.windows-enumerate.deterministic -->

- Given the agent has already listed the unchanged app's top-level windows
- When the agent requests the list of top-level windows again
- Then the result is byte-identical to the first listing apart from session metadata
