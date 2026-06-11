---
id: flow.<feature>.<action>
kind: flow
depends-on: []
---

# <Flow title>

<!--
  A flow is a step-by-step interaction sequence between the user and the
  product. It documents *what happens at each step* — the user's intent,
  what the product shows, what state changes.

  Where a use case is narrative, a flow is structural. Use both when the
  interaction has visual richness or non-trivial state transitions.
-->

## Entry points

<!-- How does the user arrive at this flow? -->

- <entry point>

## Steps

| #   | User intent                     | Product response                 | State                    |
| --- | ------------------------------- | -------------------------------- | ------------------------ |
| 1   | <what the user is trying to do> | <what the product shows or does> | <relevant state changes> |
| 2   | ...                             | ...                              | ...                      |

## Exits

<!-- How does the user leave this flow — success, abandonment, error? -->

- **<exit name>:** <what happens, what state remains>

## Related

<!-- Other flows, stories, or view models this flow touches. -->

- <id>
- <id>
