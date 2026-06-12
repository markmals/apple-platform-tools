---
id: error.uitool.node-value-timeout
kind: error
depends-on: [domain.uitool.ipc, command.uitool.node]
---

# A value-fetching read timed out on the target's main thread

## When this happens

The agent reads a node with a value-fetching facet (`--include ivars`/`props`, or any facet that invokes live getters). Those run on the target's main thread under a bounded timeout per [[domain.uitool.ipc]]; if the main-thread hop does not complete in time the op returns `TIMEOUT` rather than hang or risk the host. This is the failure mode the default structural projection avoids by never invoking getters.

> **Scope.** The value-fetching facets that trigger this are part of the deferred injection / expensive-verb half — they are not served in the cheap-read build of [[command.uitool.node]] (which accepts only the structural `class`/`frame`/`constraints`/`layer` facets and never invokes getters). This error pins the contract that half must satisfy once it lands; until then `node` cannot reach it, because the cheap-read structural facets never time out this way.

## What the user sees

A non-zero exit (exit 7 from [[domain.uitool.ipc]]) and a one-line structured JSON error on stderr with a `recover` hint. No node record is emitted on stdout. The target app is left alive. The wire code is the canonical `TIMEOUT` (exit 7) from [[domain.uitool.ipc]]'s closed vocabulary — a main-thread-hop timeout and a socket timeout share the one code and exit 7.

> `{"code":"TIMEOUT","message":"value-fetching read of 7:w0/cv/sv2/sub0 did not complete within the main-thread timeout","recover":"retry the read without --include ivars/props, or narrow the value fetch"}`

## What the user can do

- **Retry without the value-fetching facet** — read the same node with only the structural facets (`class`,`frame`,`constraints`,`layer`); the default projection and the structural facets never invoke getters and will not time out this way.
- **Retry later** — a transiently busy main thread may complete the next attempt; the read is idempotent.
- **Narrow the value fetch** — fetch fewer ivars via the value-fetching facet's `--match REGEX` narrowing. This narrowing arrives with the deferred injection half alongside `--include ivars`/`props` (specified with that pass); the standalone `ivars` verb exposes the same filter.

## Underlying cause (informational)

- The target's main thread was busy past the bounded main-thread timeout.
- A live getter / `-description` invoked by the value fetch was slow or blocked.

## Related

- [[domain.uitool.ipc]] — the main-thread marshaling rule and the timeout / exit-code mapping (`TIMEOUT` → exit 7).
- [[command.uitool.node]] — the verb that surfaces this; the cost-tier note on the value-fetching facets and their deferral to the injection half.
