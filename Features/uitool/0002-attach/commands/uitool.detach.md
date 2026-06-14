---
id: command.uitool.detach
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, domain.uitool.node-id, story.uitool.attach-release]
---

# `uitool detach` — end an inspection session

## Synopsis

```
uitool detach <app> [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the target, by pid or bundle id, as passed to `attach` |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |
| `--no-meta` | flag | no | suppress the top-level `sessionId` so output is byte-identical across sessions ([[domain.uitool.ipc]]). The list/stream `_meta` block is not emitted by `detach` (single-object result). Default off |

## Behavior

1. Resolve `<app>` to a target.
2. If the target is attached in the current session, instruct the injected server to close and unlink the socket and drop the registry ([[domain.uitool.ipc]] threading: on unload, close socket, unlink path, drop the registry; [[domain.uitool.injection]] lifecycle: detach → close socket, drop registry).
3. If the target is not attached (or already detached), treat the detach as already satisfied — idempotent.
4. Emit the result.

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses or timestamps in the default projection.

```jsonc
{
  "ok": true,
  "target": { "pid": 4821, "bundleId": "com.example.SampleAppKit" },
  "channel": "closed",
  "wasAttached": true,               // false when nothing was attached (idempotent no-op) — a command-result flag, not list/stream `_meta`; never stripped by --no-meta
  "sessionId": "7"                   // the session being torn down; stripped by --no-meta — see [[domain.uitool.ipc]]
}
```

> The exact key set above is the cheap-read MVP's documented shape. This build
> commits to the keys shown (`ok`, `target`, `channel`, `wasAttached`,
> `sessionId`) as the contract; any fields the injected server adds on teardown
> are part of the deferred injection half.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| detached (or already detached) | 0 | the result object on stdout |
| usage / bad selector | 2 | structured error on stderr |

## Invariants

- Idempotent: detaching a target that is not attached succeeds (exit 0) and reports the channel closed ([[domain.uitool.injection]] lifecycle).
- Detach closes the socket, unlinks its path, and drops the registry ([[domain.uitool.ipc]], [[domain.uitool.node-id]] — the registry is invalidated on detach).
- After a successful detach, a read query to the same target is not-attached (exit 4) until the next `attach`.
- Read-only with respect to the target's behavior: detach removes the inspection bridge but does not mutate the app's state.

## Notes

- **Cost tier: bounded (and mutating).** `detach` is one of the only mutating verbs (alongside `attach`). It is cheap relative to `attach` — no precondition stack, no injection, no bounded socket poll — but it changes session state, so it is not idempotent-in-effect the way the read verbs are.
- Detaching does not terminate the target. For a process started by [[command.uitool.launch]], detach removes only the inspection bridge and never kills the target, so the launched process keeps running and its lifecycle thereafter is the researcher's concern — `launch` does not adopt ownership past detach. See [[story.uitool.attach-release]] scenario.uitool.attach-release.app-survives-relaunched.
