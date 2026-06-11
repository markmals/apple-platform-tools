---
id: error.<domain>.<kind>
kind: error
depends-on: []
---

# <Error title>

<!--
  An error spec describes a USER-OBSERVABLE failure mode and the recovery
  affordance the product offers. It is not an exception class, an HTTP
  status, or a backend error code — it is the user's experience of the
  failure.

  Each platform implements this idiomatically. What the user sees and what
  they can do about it must converge across platforms.
-->

## When this happens

<!-- 1–2 sentences: under what conditions does the user encounter this? -->

## What the user sees

<!-- The user-visible message or affordance. Plain language. -->

> "<Example message text>"

## What the user can do

<!-- Recovery affordances. -->

- <action> — <what it does>
- <action> — <what it does>

## Underlying cause (informational)

<!-- For implementers: what technical condition triggers this user-visible
     error. NOT part of the spec contract — clients can map any number of
     internal conditions to this error. -->

- <condition>

## Related

- <related error or story id>
