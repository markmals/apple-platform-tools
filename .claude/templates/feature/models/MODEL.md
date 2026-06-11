---
id: domain.<entity>
kind: domain
depends-on: []
---

# <Entity name>

<!--
  A domain model defines the shape, identity, and invariants of an entity.
  It does NOT describe storage, serialization, or transport — those are
  implementation concerns.

  Each platform realizes this model in its own type system. The names and
  invariants are stable; the realization is idiomatic.
-->

## Shape

| Field  | Type   | Required | Notes                              |
| ------ | ------ | -------- | ---------------------------------- |
| <name> | <type> | yes/no   | <constraints, defaults, semantics> |
| <name> | <type> | yes/no   | <constraints, defaults, semantics> |

## Identity

<!-- What field(s) identify an instance uniquely? -->

- <field> (primary identifier)
- <field, field> (secondary, for human display)

## Invariants

<!-- Rules that must always hold. Validation lives wherever it's enforced;
     the spec describes WHAT must be true. -->

- <invariant> (e.g. "name is non-empty")
- <invariant> (e.g. "email, if present, is a valid email address")

## Relationships

<!-- Other domain models this one references. -->

- <other-id>: <how it relates>

## Lifecycle

<!-- If the entity has meaningful states beyond exists/doesn't-exist,
     describe them here. -->

- <state>: <when entered, what's true>

## Notes

<!-- Anything that doesn't fit above. -->
