---
id: command.uitool.list-apps
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, story.uitool.doctor-list-apps]
---

# `uitool list-apps` — list attachable processes

## Synopsis

```
uitool list-apps [--match <substring>]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `--match` | string | no | Keep only processes whose **name or bundle id** contains the value (case-insensitive substring). Default: all attachable processes. |

## Behavior

`list-apps` is **pure local detection** — like [[command.uitool.doctor]] it runs before any injection and does **not** open the IPC socket or contact a target ([[domain.uitool.ipc]] is the post-injection protocol, unused here). It enumerates the running processes that are candidates for attachment and annotates each:

1. Enumerate **every running process with an attachable task port** — not just GUI apps; background and system processes are included. `list-apps` filters nothing by kind; the agent narrows with `--match`.
2. If `--match` is given, keep only the processes whose name or bundle id matches (case-insensitive substring).
3. For each remaining process, read its pid, name, bundle id, hardened flag, and architecture.
4. Emit the listing.

The **hardened** flag and **arch** are reported so the agent can read its attach expectations off [[domain.uitool.injection]]'s attach-path table; `list-apps` itself decides nothing about which path applies and attaches to nothing. It surfaces the inputs (hardened, arch); the attach-path determination belongs to `attach`, against that table.

## Output

A JSON object on stdout carrying the apps array; each entry is one attachable process.

```jsonc
{
  "apps": [
    { "pid": 5123, "name": "Mail",         "bundleId": "com.apple.mail",          "hardened": true,  "arch": "arm64e" },
    { "pid": 6710, "name": "SampleAppKit", "bundleId": "dev.uitool.SampleAppKit", "hardened": false, "arch": "arm64" }
  ]
}
```

Output is deterministic for a given set of processes: the `apps` array is **sorted by `bundleId` ascending** (processes without a bundle id sort last, ordered by `name`), with `name` then `pid` as tiebreakers — `pid` is never the primary key (it is non-deterministic across runs). Stable key order, no addresses or timestamps. `arch` is one of `arm64e` / `arm64` / `x86_64` (a running process is a single concrete slice, never `universal`). `name` is the display name (or the executable/process name for non-app processes), distinct from `bundleId`, which may be absent for non-app processes.

An empty match yields `{"apps": []}` and exit 0 — an empty result is distinct from an error, per [[domain.uitool.ipc]]: a query matching nothing is exit 0, never a non-zero precondition code. `list-apps` represents zero matches as exit 0.

## States & exit codes

Exit codes map to [[domain.uitool.ipc]]'s table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| listing produced (including zero matches) | 0 | the apps object on stdout |
| usage / bad `--match` argument | 2 | a one-line structured error on stderr |

## Invariants

- Read-only and side-effect-free: enumerates and inspects processes, never attaches or mutates.
- Does not open the IPC socket or contact any target process.
- An empty result (zero attachable apps, or zero matches) is exit 0 with an empty `apps` array — never an error.
- Output is deterministic: stable sort, stable key order, no addresses/timestamps.

## Notes

Cost tier: **cheap/bounded** — a single process-list enumeration plus a fixed per-app metadata read (bundle id, code-signing hardened flag, arch), no target process, no socket.
