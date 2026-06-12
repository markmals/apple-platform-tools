---
id: story.uitool.find-locate
kind: story
depends-on: [domain.uitool.selector, domain.uitool.node-id, domain.uitool.node, domain.uitool.ipc, command.uitool.find]
---

# Locate a few survivors and pull narrow fields

**As a** researcher using a coding agent to reverse-engineer a running Apple app
**I want** to retrieve the matching nodes for a selector or predicate, capped to a small number and projected to just the fields I need
**So that** I get back stable handles plus a few facts for one-to-three exact nodes, cheaply enough to then drill into them.

**Independent test:** point `find` at an attached app with a predicate known to match one specific node, request a narrow field projection with a result cap, and confirm the output is one node record carrying those fields plus a stable handle, followed by a result-summary marker.

## Acceptance Criteria

### Background

- Given an app named "Mail" that is attached and responding

### Scenario 1: Retrieving matches with a narrow projection

<!-- id: scenario.uitool.find-locate.projection -->

- Given a predicate that matches one text node whose displayed text contains "Inbox"
- When the agent requests the matches projected to a handful of fields
- Then the output contains one node record carrying only the requested fields
- And the record carries a stable handle the agent can later drill into (see [[domain.uitool.node-id]])
- And a result-summary marker reports `returned: 1` and a total matched count of `1`

### Scenario 2: Capping a broad result set

<!-- id: scenario.uitool.find-locate.limit -->

- Given a selector that matches more nodes than the requested cap
- When the agent requests the matches with that result cap
- Then the output contains no more node records than the cap
- And the result-summary marker reports that the results were truncated
- And the result-summary marker still reports the full total matched count

### Scenario 3: A selector that matches nothing returns an empty result, not an error

<!-- id: scenario.uitool.find-locate.empty -->

- Given a selector that matches no nodes in the attached app
- When the agent requests the matches
- Then no node records are returned
- And the result-summary marker reports `_meta.totalMatched` of `0`
- And the command exits 0 — the empty result is distinct from a usage error (per [[domain.uitool.selector]] and [[domain.uitool.ipc]])

### Scenario 4: A malformed selector is rejected as a usage error

<!-- id: scenario.uitool.find-locate.bad-selector -->

- Given a selector or predicate that does not parse
- When the agent requests the matches
- Then no node records are returned
- And the agent is told the query is malformed, with a one-line recovery hint
- And the failure is reported as a usage error, distinct from a zero-match result (see [[error.uitool.find-bad-selector]])
