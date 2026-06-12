---
id: story.uitool.tree-walk
kind: story
depends-on: [domain.uitool.node, domain.uitool.node-id, domain.uitool.ipc, command.uitool.tree]
---

# Walk a bounded slice of the hierarchy

**As a** coding agent reverse-engineering an Apple app's layout
**I want** to read the view hierarchy from a chosen node down a fixed number of levels
**So that** I can explore structure incrementally without pulling the entire tree

**Independent test:** attach to a window with known nesting, request the tree
from its root at a small depth, and confirm the returned nodes go no deeper than
that depth and that every node carries a stable handle.

## Acceptance Criteria

### Background

- Given the agent is attached to a running target app

### Scenario 1: Walking a fixed depth from a node

<!-- id: scenario.uitool.tree-walk.bounded -->

- Given a node whose subtree is deeper than the requested depth
- When the agent requests the tree from that node at a depth of 2
- Then the result contains that node and its descendants down to 2 levels
- And no node in the result is deeper than 2 levels below the requested root

### Scenario 2: A branch cut off at the depth limit is marked

<!-- id: scenario.uitool.tree-walk.truncated -->

- Given a node whose subtree is at least 3 levels deep
- When the agent requests the tree at a depth of 1
- Then each node whose children were omitted is flagged as truncated
- And that node reports how many children it has
- And that node omits its `children` array

### Scenario 3: A fully-contained subtree is not marked truncated

<!-- id: scenario.uitool.tree-walk.complete -->

- Given a node whose entire subtree fits within the requested depth
- When the agent requests the tree at that depth
- Then no node in the result is flagged as truncated
- And every leaf node reports zero children

### Scenario 4: Walking from a chosen subtree root

<!-- id: scenario.uitool.tree-walk.subtree-root -->

- Given a node that is not a window root
- When the agent requests the tree rooted at that node
- Then the first node returned is the requested node
- And the result contains none of that node's ancestors or siblings

### Scenario 5: Walking from a stale handle

<!-- id: scenario.uitool.tree-walk.stale -->

- Given a node handle whose object no longer matches the live tree
- When the agent requests the tree rooted at that handle
- Then the agent is told the handle is stale
- And no hierarchy is returned
