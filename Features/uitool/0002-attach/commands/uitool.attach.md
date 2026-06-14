---
id: command.uitool.attach
kind: command
depends-on: [domain.uitool.injection, domain.uitool.boot, domain.uitool.server, domain.uitool.ipc, domain.uitool.node-id, story.uitool.attach-inject]
---

# `uitool attach` — inspect a running app, preserving its state

## Synopsis

```
uitool attach <pid|bundle-id> [--pretty] [--no-meta]
```

`attach` reaches into an **already-running** target and slips the inspector in
**without restarting it** — the cooperative **attach-to-running** path
([[domain.uitool.injection]]): acquire the target's task port (`task_for_pid`,
permitted for your own same-user `get-task-allow` process) and remote-`dlopen` the
[[domain.uitool.boot]] dylib, which starts the [[domain.uitool.server]]. The app
keeps its exact current on-screen state — the research default. To start a target
**fresh** from a clean state (or to inspect a cold, not-yet-running app), use
[[command.uitool.launch]] instead.

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<pid\|bundle-id>` | string | yes | the target **running** process, by pid or bundle id |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |
| `--no-meta` | flag | no | suppress the top-level `sessionId` so output is byte-identical across sessions ([[domain.uitool.ipc]]). The list/stream `_meta` block is not emitted by `attach` (single-object result). Default off |

## Behavior

1. Resolve `<pid|bundle-id>` to a **running** target process. If no such process exists, fail (exit 3, [[error.uitool.attach-not-running]]) — `attach` does not start a cold app; use [[command.uitool.launch]] for that.
2. Verify the cooperative attach-to-running preconditions ([[domain.uitool.injection]]): an Apple Silicon host, the arm64 [[domain.uitool.boot]] dylib present, `uitool` signed with the debugger entitlement, and the target being same-user and `get-task-allow`. On any failed precondition, fail (exit 6) — never silently proceed.
3. If the target already has a healthy server from the current session, reuse it and report success without bumping the session epoch ([[domain.uitool.injection]] lifecycle; idempotent).
4. Otherwise acquire the target's task port (`task_for_pid`) and remote-`dlopen` the [[domain.uitool.boot]] dylib into it — which starts the [[domain.uitool.server]] — then poll (bounded) for the per-pid socket to appear ([[domain.uitool.ipc]] transport at `/tmp/uitool-<pid>.sock`).
5. On the socket opening, bump the session epoch ([[domain.uitool.node-id]]) and perform the schema handshake (`ping`); a schema-version mismatch fails (exit 8).
6. If the handshake (`ping`) does not return within its bounded window — the socket opened but the target never answered — fail (exit 7); never report success ([[error.uitool.attach-timeout]]). When the handshake times out (exit 7) or the schema mismatches (exit 8) after the epoch was bumped in step 5, the epoch **stays incremented** — it is not rolled back — so the next attempt always gets a fresh epoch and any handle minted against the half-open session reads as stale rather than silently valid (see the epoch invariant below).
7. If the socket never opens within the bounded wait, fail (exit 4) — never report success.
8. Emit the result.

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses or timestamps in the default projection.

```jsonc
{
  "ok": true,
  "target": { "pid": 4821, "bundleId": "com.example.SampleAppKit" },
  "path": "running",           // always "running" for attach; uitool launch reports "launch"
  "channel": "open",
  "schemaVersion": "1.0.0",    // string semver from the ping handshake — see [[domain.uitool.ipc]]
  "reused": false,             // true when an existing server was reused (idempotent re-attach) — a command-result flag, not list/stream `_meta`; never stripped by --no-meta
  "sessionId": "7"             // the session marker (wire form of node-id's sessionEpoch); stripped by --no-meta — see [[domain.uitool.ipc]]
}
```

> The exact key set above is the cheap-read MVP's documented shape. Pinning it
> against the live socket — and any fields the injected server adds once the
> injection half is built — is part of that deferred half; this build commits to
> the keys shown (`ok`, `target`, `path`, `channel`, `schemaVersion`, `reused`,
> `sessionId`) as the contract the read verbs branch on.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| attached (newly or reused) | 0 | the result object on stdout |
| usage / bad selector | 2 | structured error on stderr |
| target not running | 3 | structured error on stderr (see [[error.uitool.attach-not-running]]) |
| injection failed (socket never opened) | 4 | structured error on stderr (see [[error.uitool.attach-injection-failed]]) |
| precondition failed (SIP/AMFI/LV/arch) | 6 | structured error on stderr with one-line remediation (see [[error.uitool.attach-precondition]]) |
| socket / handshake timeout | 7 | structured error on stderr (see [[error.uitool.attach-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr (see [[error.uitool.attach-schema-mismatch]]) |

## Invariants

- Idempotent: a second `attach` on an already-attached target reuses the existing server and does not bump the session epoch ([[domain.uitool.injection]]).
- The session epoch is bumped exactly once per new attach attempt that opens the socket, before the success result is emitted ([[domain.uitool.node-id]]). A failed attach (handshake timeout, exit 7; schema mismatch, exit 8) bumps the epoch in step 5 before the failure is known, and **leaves it incremented** — the epoch is never rolled back. This pins the idempotency check in step 3: a re-attach that finds a socket left over from a previous failed `ping` is treated as a **fresh attach** (re-handshake, fresh epoch), not "already attached" — a leftover socket from a half-open session is not a healthy server to reuse. "Already attached" (reuse, no bump) means a server that completed its handshake in this session.
- Never exits 0 on failure; injection that does not take is exit 4, never silent success ([[domain.uitool.injection]] invariant).
- The precondition stack gates every injection path; a failed precondition is exit 6 ([[domain.uitool.injection]]).
- `attach` is **attach-to-running only** — it preserves the target's live state and never starts or restarts the app. Starting a fresh instance is [[command.uitool.launch]]'s job ([[domain.uitool.injection]]).

## Notes

- **Cost tier: expensive (and mutating).** `attach` is one of the only non-read-only, non-idempotent-in-effect verbs (alongside `detach`); it acquires the target's task port and remote-loads the inspector, then waits on a bounded poll. The read verbs are cheap; reserve `attach`/`launch`/`detach` for session boundaries.
- **Attach-to-running preserves the target's current UI state** — the research default ("inspect it as it sits right now"). For your **own** `get-task-allow` apps this is the everyday lldb/Reveal technique on a stock Mac, not a brittle one. The brittle, version-fragile route is the *unrestricted* attach into a target you did **not** sign — the MIP-style `launchservicesd` hook — which stays deferred (HANDOFF M5, [[domain.uitool.injection]]). For a clean launch state, use [[command.uitool.launch]].
- The bounded poll/wait duration for the socket appearing is a fixed internal bound (not a flag) in this build; whether to surface it as a configurable flag waits for a second caller asking for it.
- Resolving a bundle-id to a target that is not currently running is **exit 3 (not running)**: `attach` requires an already-running process and does not auto-launch a cold app. To start a cold app under inspection, use [[command.uitool.launch]] (which owns process spawning and ownership).
