---
id: usecase.<feature>.<scenario>
kind: use-case
depends-on: []
---

# <Use case title>

<!--
  A use case is a concrete walkthrough of one user achieving one goal. Where
  stories describe a capability abstractly and tests prove discrete scenarios,
  a use case ties a sequence of actions into a coherent narrative.

  Use cases are optional. Use them when:
    - The interaction sequence is non-obvious
    - There are decisions or branches the user makes during the flow
    - You want to align the team on what "happy path X" really looks like

  Skip them when stories + flows are sufficient.
-->

## Goal

<!-- One sentence: what does the user want to achieve? -->

## Actor

<!-- Who is doing this — same persona as in the relevant story. -->

## Preconditions

<!-- What must be true before the user starts. -->

- <condition>
- <condition>

## Main success path

1. <user action or system response>
2. <user action or system response>
3. <user action or system response>

## Variations

<!-- Branches off the main path: what does the user do if X happens? -->

- **<variation name>:** <what happens, and how does it return to or end the path>

## Postconditions

<!-- What is true after the use case completes. -->

- <condition>
