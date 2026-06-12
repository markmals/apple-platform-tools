---
id: story.uitool.find-count
kind: story
depends-on: [domain.uitool.selector, command.uitool.find]
status: draft
---

# Size a selector before paying for it

**As a** researcher using a coding agent to reverse-engineer a running Apple app
**I want** to ask how many nodes a selector or predicate matches without pulling any of them back
**So that** I can tell whether the query is too broad to drill into before spending context budget retrieving results.

**Independent test:** point `find` at an attached app with a selector that is known to match a specific number of nodes (e.g. its `NSTableView`s), pass the count-only flag, and confirm the output reports exactly that count and nothing else.

## Acceptance Criteria

### Background

- Given an app named "Mail" that is attached and responding

### Scenario 1: Counting matches for a selector

<!-- id: scenario.uitool.find-count.matches -->

- Given a selector that matches three nodes in the attached app
- When the agent asks for the match count only
- Then the result reports `_meta.totalMatched` of `3`
- And no matched nodes are returned in the output

### Scenario 2: Counting a selector that matches nothing

<!-- id: scenario.uitool.find-count.zero -->

- Given a selector that matches no nodes in the attached app
- When the agent asks for the match count only
- Then the result reports `_meta.totalMatched` of `0`
- And the command exits 0 — a valid 0-match query is not an error (per [[domain.uitool.ipc]])

### Scenario 3: Sizing a too-broad selector

<!-- id: scenario.uitool.find-count.broad -->

- Given a selector that matches several hundred nodes in the attached app
- When the agent asks for the match count only
- Then the result reports the full total matched count
- And the count is reported regardless of any result cap the agent would otherwise apply
