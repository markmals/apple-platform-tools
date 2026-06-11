---
id: story.<feature>.<capability>
kind: story
depends-on: []
---

# <Capability title>

<!--
  Authored using the `writing-user-stories` skill. The story describes ONE
  user-observable capability, paired with Gherkin acceptance criteria that
  are externally testable.
-->

**As a** <real user persona>
**I want** <capability the user performs>
**So that** <user-visible outcome or value>

**Independent test:** <how this story can be verified end-to-end on its own — e.g. "user signs in, performs the action, sees the outcome">

## Acceptance Criteria

<!-- Optional: Background runs before each scenario; keep it ≤ 4 lines. -->

### Background

- Given <named character or stable state>

### Scenario 1: <specific behavior>

<!-- id: scenario.<feature>.<capability>.<short-name> -->

- Given <state>
- And <state>
- When <single user action>
- Then <observable outcome>
- And <observable outcome>

### Scenario 2: <another behavior>

<!-- id: scenario.<feature>.<capability>.<short-name> -->

- Given <state>
- When <single user action>
- Then <observable outcome>

<!--
  Add scenarios as needed. If you reach ~6+ scenarios, the story is probably
  too large — split it. See the writing-user-stories skill for guidance.

  Each scenario sub-ID becomes a test name prefix in every platform's tests:
  Vitest:  it('[scenario.<feature>.<capability>.<short-name>] ...')
  Swift:   @Test("[scenario.<feature>.<capability>.<short-name>] ...")
  Kotlin:  @DisplayName("[scenario.<feature>.<capability>.<short-name>] ...")
-->
