---
id: command.uitool.attach
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, domain.uitool.node-id, story.uitool.attach-inject]
---

# `uitool attach` — make a target app inspectable

## Synopsis

```
uitool attach <pid|bundle-id> [--relaunch] [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<pid\|bundle-id>` | string | yes | the target process, by pid or bundle id |
| `--relaunch` | flag | no | use the relaunch-inject path (Path A) instead of the default running-process attach path (Path B). See [[domain.uitool.injection]] |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |
| `--no-meta` | flag | no | suppress the top-level `sessionId` so output is byte-identical across sessions ([[domain.uitool.ipc]]). The list/stream `_meta` block is not emitted by `attach` (single-object result). Default off |

## Behavior

1. Resolve `<pid|bundle-id>` to a target process. If no such process exists, fail (exit 3).
2. Verify the injection precondition stack ([[domain.uitool.injection]]); on any failed precondition, fail (exit 6) — never silently proceed.
3. If the target is already attached in the current session, reuse the existing server and report success without bumping the session epoch ([[domain.uitool.injection]] lifecycle; idempotent).
4. Otherwise inject via the selected path — running-attach (Path B) by default, or relaunch (Path A) under `--relaunch` — then poll (bounded) for the per-pid socket to appear ([[domain.uitool.ipc]] transport at `/tmp/uitool-<pid>.sock`).
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
  "path": "running",           // "running" (Path B, default) or "relaunch" (Path A, --relaunch)
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
- `--relaunch` is opt-in; the default is running-attach (Path B) ([[domain.uitool.injection]]).

## Notes

- **Cost tier: expensive (and mutating).** `attach` is one of the only non-read-only, non-idempotent-in-effect verbs (alongside `detach`); it spawns or hijacks a process and waits on a bounded poll. The read verbs are cheap; reserve `attach`/`detach` for session boundaries.
- Path B (the default, running-attach) preserves the target's current UI state but is brittle and version-fragile; Path A (`--relaunch`) loses that state but is robust across OS/app updates ([[domain.uitool.injection]]). The proven first-party route is the MIP-style launchservicesd hook (M5).
- The bounded poll/wait duration for the socket appearing is an injection-half tuning concern: this build keeps it a fixed internal bound (not a flag), and whether to surface it as a configurable flag is deferred to the injection half — there is no second caller asking for it yet.
- Resolving a bundle-id to a target that is not yet running is **exit 3 (not running)** in this build: `attach` requires an already-running process and does not auto-launch a cold app. Auto-launching a cold bundle-id (a relaunch-from-cold path) is deferred to the injection half, where Path A's process ownership is defined.
