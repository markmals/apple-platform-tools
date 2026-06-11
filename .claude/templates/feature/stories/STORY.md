---
id: story.<tool>.<capability>
kind: story
depends-on: []
---

# <Capability title>

<!--
  Authored using the `writing-user-stories` skill. The story describes ONE
  user-observable capability, paired with Gherkin acceptance criteria that
  are externally testable.
-->

**As a** coding agent
**I want** <capability the agent performs>
**So that** <observable outcome or value>

<!-- This repo is agent-first: "As a coding agent" is the sanctioned actor.
     See `Specs/CONVENTIONS.md` → "The actor is a coding agent". -->

**Independent test:** <how this story can be verified end-to-end on its own — e.g. "run `<tool> <verb> <args>`, assert the JSON payload and exit code">

## Acceptance Criteria

<!-- Optional: Background runs before each scenario; keep it ≤ 4 lines. -->

### Background

- Given <named character or stable state>

### Scenario 1: <specific behavior>

<!-- id: scenario.<tool>.<capability>.<short-name> -->

- Given <state>
- And <state>
- When <single agent action>
- Then <observable outcome>
- And <observable outcome>

### Scenario 2: <another behavior>

<!-- id: scenario.<tool>.<capability>.<short-name> -->

- Given <state>
- When <single agent action>
- Then <observable outcome>

<!--
  Add scenarios as needed. If you reach ~6+ scenarios, the story is probably
  too large — split it. See the writing-user-stories skill for guidance.

  Each scenario sub-ID becomes a test name prefix in the tool's Swift Testing suite:
  @Test("[scenario.<tool>.<capability>.<short-name>] ...")
-->
