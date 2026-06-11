---
id: error.<tool>.<kind>
kind: error
depends-on: []
---

# <Error title>

<!--
  An error spec describes an OBSERVABLE failure mode and the recovery
  affordance the tool offers. It is not an exception class or an internal
  error code — it is the agent's (or user's) experience of the failure:
  the structured message on stderr and the exit code.

  See the `AgentCLI` contract for the shared error/exit-code shape.
-->

## When this happens

<!-- 1–2 sentences: under what conditions does the caller encounter this? -->

## What the caller sees

<!-- The structured error on stderr and the exit code. -->

> "<Example message text>"

Exit code: `<2–8>`

## What the caller can do

<!-- Recovery affordances — what the agent or user does next. -->

- <action> — <what it does>
- <action> — <what it does>

## Underlying cause (informational)

<!-- For implementers: what technical condition triggers this error. NOT part
     of the spec contract — the implementation can map any number of internal
     conditions to this error. -->

- <condition>

## Related

- <related error or story id>
