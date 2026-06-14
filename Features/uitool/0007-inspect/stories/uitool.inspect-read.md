---
id: story.uitool.inspect-read
kind: story
depends-on: [domain.uitool.registry, domain.runtime.reflection, domain.uitool.ipc, domain.uitool.node-id]
---

# Inspect a live object's ivars and properties

**As a** coding agent reverse-engineering a macOS app
**I want** to read a live object's instance variables and (on demand) its property
values
**So that** I can see the private state behind a control instead of guessing from
its public geometry.

**Independent test:** Attach to the harness app, locate a node, inspect it, and
observe its ivars with values and its declared properties; the target stays alive,
and no getter ran unless `--invoke` was passed.

## Acceptance Criteria

### Background

- Given the agent has attached to a target and holds a node id from a read verb ([[domain.uitool.node-id]])

### Scenario 1: Read ivars and class reflection by default, running no target code

<!-- id: scenario.uitool.inspect-read.ivars-default -->

- Given a node id for a live object
- When the agent inspects it without `--invoke`
- Then the result reports the object's runtime class, its ivars with their current values, and its declared properties, methods, and protocols
- And no property getter was invoked — the default read runs none of the target's code
- And the target app is still running

### Scenario 2: An object-typed ivar is reported as its class, never a pointer or description

<!-- id: scenario.uitool.inspect-read.object-ivar -->

- Given a node whose object has an ivar holding another object
- When the agent inspects it
- Then that ivar's value is the held object's runtime class (plus its node id when it is a registered view), never a raw pointer and never an invoked `-description`

### Scenario 3: A regex narrows a large object to the fields of interest

<!-- id: scenario.uitool.inspect-read.match -->

- Given a node whose object has many ivars and properties
- When the agent inspects it with a `--match` pattern
- Then only the ivars and properties whose names match are reported

### Scenario 4: `--invoke` reads property values from the getters

<!-- id: scenario.uitool.inspect-read.invoke -->

- Given a node id for a live object
- When the agent inspects it with `--invoke`
- Then the declared properties additionally carry the values their getters return
- And each getter ran on the target main thread under the bounded timeout

### Scenario 5: A stale node id is refused, never a recycled-pointer read

<!-- id: scenario.uitool.inspect-read.stale -->

- Given a node id whose object has been torn down or whose pointer was recycled by a different class
- When the agent inspects it
- Then the inspect fails with `STALE_NODE` (exit code 5, [[error.uitool.node-stale]])
- And no memory at the recycled pointer was dereferenced

### Scenario 6: A getter that blocks the main thread times out under `--invoke`

<!-- id: scenario.uitool.inspect-read.invoke-timeout -->

- Given a node whose property getter blocks the target main thread
- When the agent inspects it with `--invoke`
- Then the inspect fails with `TIMEOUT` (exit code 7, [[error.uitool.node-value-timeout]])
- And the target app is left alive, never hung

### Scenario 7: Known-unsafe classes and ivars are skipped, not read

<!-- id: scenario.uitool.inspect-read.safety -->

- Given a node whose object (or one of its ivars) is on the `RuntimeSafety` unsafe list ([[domain.runtime.reflection]])
- When the agent inspects it
- Then the unsafe ivars are omitted rather than read, and unsafe getters are not invoked even under `--invoke`
