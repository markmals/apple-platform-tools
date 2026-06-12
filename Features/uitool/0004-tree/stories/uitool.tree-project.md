---
id: story.uitool.tree-project
kind: story
depends-on: [domain.uitool.node, domain.uitool.selector, command.uitool.tree]
---

# Project only the fields I need

**As a** coding agent skimming a large hierarchy
**I want** to choose which facts each node reports
**So that** a structural skim stays tiny and I only pay for detail when I ask for it

**Independent test:** request the same subtree twice — once with the default
projection and once asking for only a node's handle and class — and confirm the
second result carries only those fields per node.

## Acceptance Criteria

### Background

- Given the agent is attached to a running target app

### Scenario 1: Restricting to a chosen set of fields

<!-- id: scenario.uitool.tree-project.narrow -->

- Given a node with a populated subtree
- When the agent requests the tree projecting only the handle and class of each node
- Then every node in the result carries its handle and class
- And no node in the result carries any other field

### Scenario 2: Default projection when no fields are chosen

<!-- id: scenario.uitool.tree-project.default -->

- Given a node with a populated subtree
- When the agent requests the tree without naming any fields
- Then every node in the result carries the default projection defined by [[domain.uitool.node]]

### Scenario 3: An unknown field name is rejected

<!-- id: scenario.uitool.tree-project.unknown-field -->

- Given a node with a populated subtree
- When the agent requests the tree projecting a field name that does not exist
- Then the agent is told the field name is invalid
- And no hierarchy is returned
