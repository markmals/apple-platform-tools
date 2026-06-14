---
id: command.uitool.launch
kind: command
depends-on: [domain.uitool.injection, domain.uitool.boot, domain.uitool.server, domain.uitool.ipc, domain.uitool.node-id, story.uitool.launch]
---

# `uitool launch` — start an app under inspection

## Synopsis

```
uitool launch <bundle-id|path> [--replace] [--pretty] [--no-meta] [-- <app-args>…]
```

`launch` brings a target up **fresh** with the inspector already loaded — the
cooperative **launch path** ([[domain.uitool.injection]]): `posix_spawn` under
`DYLD_INSERT_LIBRARIES=…/UIToolBoot.dylib` so the [[domain.uitool.boot]] dylib
loads before `main` and starts the [[domain.uitool.server]]. Use it when a clean
launch state is wanted. To inspect an app **as it sits right now**, preserving its
on-screen state, use [[command.uitool.attach]] instead.

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<bundle-id\|path>` | string | yes | the app to launch, by bundle id or path to a `.app` |
| `--replace` | flag | no | if a same-user instance of the target is already running, terminate it first, then launch fresh. Default off — without it, an already-running target is a usage error directing you to `attach` (see Behavior) |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |
| `--no-meta` | flag | no | suppress the top-level `sessionId` so output is byte-identical across sessions ([[domain.uitool.ipc]]). The list/stream `_meta` block is not emitted by `launch` (single-object result). Default off |
| `-- <app-args>…` | strings | no | arguments passed through to the launched app after `--`. Default none |

## Behavior

1. Resolve `<bundle-id|path>` to a launchable `.app` bundle. If none resolves, fail (exit 3, [[error.uitool.launch-not-found]]).
2. If a same-user instance of the target is already running: without `--replace`, fail (exit 2) with a message directing the agent to [[command.uitool.attach]] (to inspect it preserving state) or to re-run with `--replace`. With `--replace`, terminate the running instance(s) first.
3. Verify the cooperative launch preconditions ([[domain.uitool.injection]]): Apple Silicon host, the **arm64** [[domain.uitool.boot]] dylib present, and the target permits dyld environment variables (a debug build, or one carrying `com.apple.security.cs.allow-dyld-environment-variables`). On any failed precondition, fail (exit 6, [[error.uitool.attach-precondition]]) — never silently proceed.
4. `posix_spawn` the bundle's executable with `DYLD_INSERT_LIBRARIES` pointing at the arm64 boot dylib and any `-- <app-args>` appended, then poll (bounded) for the per-pid socket to appear ([[domain.uitool.ipc]] transport at `/tmp/uitool-<pid>.sock`).
5. On the socket opening, bump the session epoch ([[domain.uitool.node-id]]) and perform the schema handshake (`ping`); a schema-version mismatch fails (exit 8, [[error.uitool.attach-schema-mismatch]]).
6. If the handshake does not return within its bounded window — the socket opened but the target never answered — fail (exit 7, [[error.uitool.attach-timeout]]); the epoch **stays incremented** (it is never rolled back, [[command.uitool.attach]] epoch invariant).
7. If the socket never opens within the bounded wait — the spawn failed to exec, or the dylib failed to load — fail (exit 4, [[error.uitool.attach-injection-failed]]); never report success.
8. Emit the result.

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses or timestamps in the default projection.

```jsonc
{
  "ok": true,
  "target": { "pid": 4930, "bundleId": "com.example.SampleAppKit" },
  "path": "launch",            // always "launch" for this command
  "channel": "open",
  "schemaVersion": "1.0.0",    // string semver from the ping handshake — see [[domain.uitool.ipc]]
  "replaced": false,           // true when --replace terminated a prior running instance first — a command-result flag, never stripped by --no-meta
  "sessionId": "8"             // the session marker (wire form of node-id's sessionEpoch); stripped by --no-meta
}
```

> The key set (`ok`, `target`, `path`, `channel`, `schemaVersion`, `replaced`,
> `sessionId`) is the contract the read verbs branch on, parallel to
> [[command.uitool.attach]]'s. `path` is always `"launch"` here; `attach` reports
> `"running"`.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| launched & attached | 0 | the result object on stdout |
| usage / already running without `--replace` | 2 | structured error on stderr |
| app not found / not launchable | 3 | structured error on stderr (see [[error.uitool.launch-not-found]]) |
| injection failed (socket never opened) | 4 | structured error on stderr (see [[error.uitool.attach-injection-failed]]) |
| precondition failed (arch / arm64 injectable / dyld-env) | 6 | structured error on stderr with one-line remediation (see [[error.uitool.attach-precondition]]) |
| socket / handshake timeout | 7 | structured error on stderr (see [[error.uitool.attach-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr (see [[error.uitool.attach-schema-mismatch]]) |

## Invariants

- **`launch` always starts a new process**, so it always opens a **new session
  with a fresh epoch** ([[domain.uitool.node-id]]); it is never idempotent the way
  a re-`attach` is, and never reports `reused`. Two `launch`es are two sessions.
- **`launch` loses the target's prior on-screen state by design** — it is a clean
  launch. Preserving live state is [[command.uitool.attach]]'s job
  ([[domain.uitool.injection]] trade-off).
- **Never terminates a running instance without `--replace`.** A silent kill could
  lose the user's data; `launch` refuses (exit 2) and names the explicit path
  forward (repo "no silent fallback" rule).
- Never exits 0 on failure; a spawn whose socket never opens is exit 4, never
  silent success ([[domain.uitool.injection]] invariant).
- The cooperative launch precondition stack gates the spawn; a failed precondition
  is exit 6 ([[domain.uitool.injection]]).
- Read-only with respect to the target's behavior once attached: v1 ships no
  write/mutation op ([[domain.uitool.ipc]]).

## Notes

- **Cost tier: expensive (and mutating).** Like `attach`, `launch` spawns a
  process and waits on a bounded poll; reserve it for session boundaries.
- **`launch` vs `attach`.** `launch` = fresh instance, clean state, robust across
  OS/app updates; `attach` = the already-running instance, live state preserved.
  `--replace` is the old `attach --relaunch` semantics relocated to where the
  spawn actually lives — relaunch *is* a launch.
- **Process ownership after detach.** `launch` owns the process it spawned only
  until `detach`; `detach` removes the inspection bridge and **never** terminates
  the target ([[command.uitool.detach]]), so a launched process keeps running and
  its lifecycle thereafter is the researcher's concern
  ([[story.uitool.attach-release]] scenario.uitool.attach-release.app-survives-relaunched).
- The bounded poll/wait for the socket is a fixed internal bound (not a flag) in
  this build, as in [[command.uitool.attach]]; surfacing it as configurable is
  deferred until there is a second caller asking for it.
