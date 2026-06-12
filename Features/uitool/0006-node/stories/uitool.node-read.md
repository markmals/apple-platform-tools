---
id: story.uitool.node-read
kind: story
depends-on: [domain.uitool.node, domain.uitool.node-id, command.uitool.node]
---

# Read one located node deeply

**As a** coding agent reverse-engineering a running macOS app
**I want** to read the deeper facets of a single node I have already located
**So that** I learn its real class hierarchy, constraints, and layer without pulling the whole tree

**Independent test:** attach to a target with a known view tree, locate a node and capture its id, then read that node with selected `--include` facets and assert the returned record carries the requested facets and no unrequested facets, for exactly that node.

## Acceptance Criteria

### Background

- Given the agent is attached to a running target app
- And the agent holds a valid node id for a node in that target

### Scenario 1: Reading a node with no extra facets requested

<!-- id: scenario.uitool.node-read.default -->

- When the agent reads that node without requesting any extra facets
- Then the output is a single record describing that one node
- And the record carries the default-projection fields of [[domain.uitool.node]]
- And the record does not carry the pull-on-demand facets (`superclasses`, the full constraint list, `layer`)
- And the command exits successfully

### Scenario 2: Reading a node with selected facets

<!-- id: scenario.uitool.node-read.included -->

- Given the agent holds a valid node id for a node that has touching constraints and a backing layer
- When the agent reads that node requesting the constraints and layer facets
- Then the returned record carries the inlined constraint list and the layer facet
- And it does not carry facets that were not requested
- And the command exits successfully

### Scenario 3: A requested facet does not apply to the node

<!-- id: scenario.uitool.node-read.facet-absent -->

- Given the agent holds a valid node id for a node that has no backing layer
- When the agent reads that node requesting the layer facet
- Then the returned record carries the requested facet as `null` rather than omitting it
- And the command exits successfully

### Scenario 4: The node is read for one node only, never its subtree

<!-- id: scenario.uitool.node-read.single -->

- Given the agent holds a valid node id for a node that has child nodes
- When the agent reads that node with any facets
- Then the returned record describes exactly one node
- And it does not contain the child nodes' records
- And the command exits successfully
