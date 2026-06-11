---
id: vm.<tool>.<view>
kind: view-model
depends-on: []
---

# <View model name>

<!--
  A view model defines the state, actions, transitions, and derived values
  for one stateful surface. It is a behavioral spec for logic that holds
  state across interactions.

  This is the WHAT; the Swift realization is the HOW. View models are rare in
  this repo — most tools are stateless command verbs. See `Specs/CONVENTIONS.md`.
-->

## Purpose

<!-- One sentence: what user-facing view does this VM back? -->

## State

```
{
  <field>: <type>,
  <field>: <type>,
  status: <enum of states>,
  ...
}
```

| Field  | Type   | Notes                                         |
| ------ | ------ | --------------------------------------------- |
| <name> | <type> | <when present, when null, what it represents> |

### Status states

- `<state>`: <when entered>
- `<state>`: <when entered>

## Derived values

<!-- Computed from state; not stored separately. -->

- `<name>`: <how it's derived from state>

## Actions

| Action           | Inputs | Effect                                       |
| ---------------- | ------ | -------------------------------------------- |
| `<name>(<args>)` | <args> | <state change, side effect, error condition> |

## Transitions

<!-- The state machine. Use this section if status has more than two states. -->

```
idle  ──submit()──>  submitting
submitting  ──success──>  success
submitting  ──error──>  error
error  ──retry()──>  submitting
error  ──dismiss()──>  idle
```

## Invariants

<!-- Rules that must always hold across state changes. -->

- <invariant> (e.g. "cannot submit when items is empty")
- <invariant>

## Initial state

<!-- What state does this view model have when first instantiated? -->

```
{ ... }
```

## Notes

<!-- Anything that doesn't fit above. -->
