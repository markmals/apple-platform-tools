---
id: story.uitool.classes-browse
kind: story
depends-on: [domain.runtime.reflection, domain.uitool.ipc, domain.uitool.selector]
---

# Browse and reflect the target's classes

**As a** coding agent reverse-engineering an app's architecture
**I want** to list the loaded classes matching a pattern and reflect one class
**So that** I can map the app's type graph and read what a class declares without
an instance.

**Independent test:** Attach to the harness, list the classes matching a known
class name, then reflect that class and observe its superclass chain and members.

## Acceptance Criteria

### Background

- Given the agent has attached to a target ([[domain.uitool.ipc]])

### Scenario 1: List the loaded classes matching a pattern

<!-- id: scenario.uitool.classes-browse.list -->

- When the agent runs `classes --match` with a pattern that matches a loaded class
- Then it exits 0 with the sorted names of the matching loaded classes and a count

### Scenario 2: Reflect one class's declared shape

<!-- id: scenario.uitool.classes-browse.reflect -->

- When the agent runs `classes --class NSVisualEffectView`
- Then it exits 0 with that class's superclass chain, ivars (name + type), properties, methods, and protocols
- And no instance value is read and no target code runs

### Scenario 3: An unloaded class name is a valid empty result

<!-- id: scenario.uitool.classes-browse.unloaded -->

- When the agent runs `classes --class` with a name that is not a loaded class
- Then it exits 0 with `loaded: false`, never an error

### Scenario 4: Neither mode is a usage error

<!-- id: scenario.uitool.classes-browse.usage -->

- When the agent runs `classes` with neither `--match` nor `--class`
- Then it fails with exit code 2 — a bare classes would be an unbounded dump

### Scenario 5: The list is bounded

<!-- id: scenario.uitool.classes-browse.bounded -->

- Given more matching classes than `--limit`
- When the agent runs `classes --match` with that limit
- Then at most `--limit` names are returned and `truncated` is true
