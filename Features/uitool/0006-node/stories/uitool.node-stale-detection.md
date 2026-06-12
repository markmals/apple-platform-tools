---
id: story.uitool.node-stale-detection
kind: story
depends-on: [domain.uitool.node-id, domain.uitool.ipc, command.uitool.node]
---

# Find out when a held node id is no longer valid

**As a** coding agent that may read a node many turns after locating it
**I want** to be told distinctly when a node id no longer points at the object I located
**So that** I re-locate instead of trusting a stale or recycled answer

**Independent test:** locate a node and capture its id, cause the held id to no longer resolve to the recorded object (re-attach, or mutate the tree so the path now resolves to a different class), then read the node and assert a distinct staleness exit code rather than a successful read.

## Acceptance Criteria

### Background

- Given the agent is attached to a running target app

### Scenario 1: Reading a node id minted before a re-attach

<!-- id: scenario.uitool.node-stale-detection.epoch -->

- Given the agent holds a node id minted during an earlier attach session
- And the agent has since re-attached to the target
- When the agent reads that node
- Then the agent is told the node id is stale
- And the staleness exit code from [[domain.uitool.ipc]] is returned
- And no node record is emitted on stdout

### Scenario 2: Reading a node whose path now resolves to a different object

<!-- id: scenario.uitool.node-stale-detection.recycled -->

- Given the agent holds a node id for a node of a known class
- And the target's tree has changed so that path now resolves to an object of a different class
- When the agent reads that node
- Then the agent is told the node id is stale
- And the staleness exit code from [[domain.uitool.ipc]] is returned
- And no node record is emitted on stdout

### Scenario 3: A stale read is distinct from an empty result

<!-- id: scenario.uitool.node-stale-detection.distinct -->

- Given the agent holds a stale node id
- When the agent reads that node
- Then the exit code is the staleness code, not the success code
- And the error output tells the agent to re-locate the node rather than re-issue the same read
