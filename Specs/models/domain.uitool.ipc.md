---
id: domain.uitool.ipc
kind: domain
depends-on: [domain.uitool.node-id, domain.uitool.node, domain.uitool.injection]
---

# IPC Protocol

The wire contract between the `uitool` CLI and the injected headless server (`UIToolServer`, hosted by `UIToolBoot`). Derived from HANDOFF §7 + §8.1.

> **Scope note.** This protocol is the **deferred injection half** of `uitool` — the CLI and the injected `UIToolServer` are separately built and talk over this socket. The cheap-read MVP (`windows` / `tree` / `find` / `node`) is built on the pure `UIToolCore` first; this spec pins the contract the server must satisfy once the injection half lands. Specs are intact; only the impl is deferred. The pure core's projection, exit-code, and JSON-Lines behavior already obey the determinism rules below.

## Transport

- **Unix domain socket** at `/tmp/uitool-<pid>.sock`, `chmod 0600` to the dev user.
- The injected dylib creates the socket on load and unlinks it on unload.
- Rejected for v1: Mach ports (bootstrap friction), localhost TCP (any local process could connect).

## Message shape (JSON-Lines)

One request object in, one response (or a stream of node objects) out. Synchronous and stateless per request; the server holds the live object graph.

```jsonc
// request
{"v":1,"id":7,"op":"hierarchy","window":"auto","maxDepth":3,"include":["class","frame","layer"]}
// response (one line) — `data` is a raw snapshot (a Capture / WindowSnapshot subtree),
// NOT a pre-projected node: the CLI applies rounding, key order, and node-id
// stringification ([[domain.uitool.node]]). The server holds no policy.
{"v":1,"id":7,"ok":true,"data":{ /* a Capture: {epoch, windows:[…]} or a subtree */ }}
// error
{"v":1,"id":7,"ok":false,"error":{"code":"STALE_NODE","message":"…","recover":"…"}}
```

| Field | Type | Notes |
| --- | --- | --- |
| `v` | int | protocol version; mismatch is a hard error (exit 8) |
| `id` | int | echoed in the response |
| `op` | string | the operation |
| `ok` | bool | success flag |
| `data` / `error` | object | one or the other |
| `error.code` | string | machine code, drawn from the closed vocabulary below |
| `error.recover` | string | one-line recovery hint; never a stack trace |
| `schemaVersion` | string | semver, e.g. `"1.0.0"` — in every payload and in `ping` (HANDOFF §8.4) |
| `sessionId` | string | identifies the attach session; the wire form of node-id's `sessionEpoch`. Suppressed by `--no-meta` |
| `_meta` | object | list/stream metadata: `{returned, truncated, totalMatched}`. Suppressed by `--no-meta` |

**Envelope metadata.** Every response carries `schemaVersion` (string). Unless `--no-meta` is passed, a response also carries a top-level `sessionId` (string) — the wire form of [[domain.uitool.node-id]]'s `sessionEpoch`, so the agent can detect a re-attach — and list/stream responses carry `_meta: {returned, truncated, totalMatched}`. `truncated` is the single canonical "more exist past the limit/depth" flag (never a second `limitHit`). `--no-meta` strips `sessionId`/`_meta` so output is byte-identical across sessions. Error responses (`ok:false`) carry `v` / `id` / `schemaVersion` and the `error` object, but not `sessionId`/`_meta`; examples may elide `v`/`id`/`schemaVersion` for brevity. (The attach-time/local verbs `doctor` and `list-apps` answer before any IPC socket exists, so their result objects are not bound by this envelope.)

## Operations

One `op` per request. The vocabulary is closed; an unknown `op` is a hard error. The **cheap-read MVP** verbs map onto a small subset:

| `op` | CLI verb | Reads | Notes |
| --- | --- | --- | --- |
| `hierarchy` | `tree` | view tree, bounded by `maxDepth` | the spine read; emits a root [[domain.uitool.node]] with nested children |
| `hierarchy` (maxDepth 0) | `node` | one node, no descendants | the single-node read is `hierarchy` pinned to depth 0 — `node` binds to the tree op at `maxDepth: 0` rather than a separate op |
| `find` | `find` | descendant match against a [[domain.uitool.selector]] | streams matching nodes; sized by `--limit` / `--count-only` ([[domain.uitool.selector]]) |
| `windows` | `windows` | the app's top-level windows | a list response; each entry is a window-rooted [[domain.uitool.node]] |
| `inspect` | `inspect` | one object's ivar values + class reflection (`--invoke` adds getter values) | resolves a node id to a live object via [[domain.uitool.registry]]; the value-fetching op ([[command.uitool.inspect]], Phase 3.5) |

The `inspect` value-fetching op is specified in [[command.uitool.inspect]] (Phase 3.5): ivar reads are safe and default; **getter invocation** is gated behind `--invoke`, runs on the target main thread under the bounded timeout, and is safety-screened. Raw setter **mutation** stays out of scope — v1 is read-only.

## Default mode: structural, no-invoke

Reading ivar **memory** is safe (no target code runs) and is `inspect`'s default. Invoking property **getters** / `-description` runs the target's own code **inside someone else's process** — it can deadlock the main thread, mutate state, or crash the host. So getter invocation is gated behind `inspect --invoke`, runs on the target main thread under a hard per-query timeout, and is safety-screened ([[command.uitool.inspect]]). The cheap-read verbs (`windows` / `tree` / `find` / `node`) are all structural, no-invoke reads; `inspect` without `--invoke` is too.

## Threading (load-bearing)

- The socket accept/read loop runs on a dedicated **background** thread — never block the host main thread.
- **All AppKit reads run on the target's main thread**, marshaled per request with a bounded timeout (≈500 ms); on timeout return `TIMEOUT` rather than hang.
- Per-request main-thread work is tiny and bounded by `maxDepth`: snapshot on main, serialize to JSON off-main. Avoid the snapshot-image path entirely (it mutates the hierarchy).
- On dylib unload / app quit: close socket, unlink path, drop the registry.

## Error codes (the closed vocabulary)

`error.code` is drawn from a fixed set. These are the canonical wire codes — the CLI maps each to an exit code, the agent branches on the code without parsing `message`/`recover` prose.

| `error.code` | Exit | Source | Meaning |
| --- | --- | --- | --- |
| `BAD_SELECTOR` | 2 | [[domain.uitool.selector]] | the `--match` regex was uncompilable, or a usage/selector error |
| `UNKNOWN_FIELD` | 2 | projection | a `--fields` path that names no [[domain.uitool.node]] field |
| `BAD_PREDICATE` | 2 | projection | a malformed `--where` predicate |
| `NOT_ATTACHED` | 4 | [[domain.uitool.injection]] | no live session for the target (or injection failed) |
| `STALE_NODE` | 5 | [[domain.uitool.node-id]] | a held node id failed re-validation against the live graph |
| `NO_WINDOWS` | (see note) | windows | the attached app has no top-level windows to root a read at |
| `TIMEOUT` | 7 | this spec (threading) | a main-thread hop exceeded the ≈500 ms bound, or a socket timeout |

`UNKNOWN_FIELD` and `BAD_PREDICATE` are **distinct** codes (not a single `BAD_PROJECTION`): an unknown `--fields` path and a malformed `--where` predicate are different agent-fixable mistakes, so they get different codes — both exit 2. `BAD_SELECTOR` covers an uncompilable `--match` regex specifically (the [[domain.uitool.selector]] engine throws at `Regex` construction); the projection codes never collapse into it.

**`NO_WINDOWS` is not an error exit.** An attached app with zero top-level windows is a valid, empty result, not a failure: `windows` returns **exit 0** with `_meta.totalMatched: 0` and an empty list. `NO_WINDOWS` is the explanatory `error.code` carried on stderr's structured object only where a verb that *requires* a window to root at (e.g. a `tree`/`find` with `window: "auto"` and no candidate) cannot proceed — in that case it surfaces as the verb's empty result, never as a non-zero exit. The agent reads `_meta`, not the exit code, to tell empty from broken.

## Exit-code mapping (CLI)

The agent branches on exit code without parsing prose:

| Exit | Meaning |
| --- | --- |
| 0 | ok |
| 2 | usage / `BAD_SELECTOR` / `UNKNOWN_FIELD` / `BAD_PREDICATE` |
| 3 | app not running |
| 4 | `NOT_ATTACHED` / injection failed |
| 5 | `STALE_NODE` ([[domain.uitool.node-id]]) |
| 6 | SIP/AMFI/LV/arch precondition failed ([[domain.uitool.injection]]) |
| 7 | socket / `TIMEOUT` |
| 8 | schema-version mismatch |

A successful query that matches **nothing** is exit **0** (with `_meta.totalMatched: 0`), never a non-zero code — see Notes.

- **Exit 3 (app not running) and exit 6 (precondition) are attach-time only.** Exit 3 is emitted by `attach` while resolving/launching a named target; exit 6 by `doctor` and `attach` (the precondition gate). `list-apps` emits neither — it enumerates (0/2 only). Post-attach query verbs assume a live session; an unreachable session surfaces as **exit 4** (`NOT_ATTACHED`) or **exit 7** (`TIMEOUT`), never 3 or 6.
- This table governs the **CLI↔agent control channel only** — build- and install-time failures use their own conventions and do not map to these codes.

## Invariants

- Every payload carries `schemaVersion` — a semver **string** (e.g. `"1.0.0"`), distinct from the int protocol version `v`; carried in `ping` too. Additive changes only within a major.
- `error.code` is always one of the closed vocabulary above. No ad-hoc codes; no placeholder strings.
- Never exit 0 on failure. Errors also print a one-line structured JSON object to stderr.
- The schema handshake on `ping` is what keeps the separately-built CLI and dylib from desyncing.

## Relationships

- [[domain.uitool.server]] — the in-target unit that speaks this protocol; it ships a raw `Capture` as a read's `data` and the CLI projects it. The threading invariants above are its law.
- [[domain.uitool.boot]] — the dylib that hosts the server and creates/unlinks the socket.
- [[domain.uitool.node]] — the projected shape the CLI derives from the raw `data` snapshot.
- [[domain.uitool.node-id]] / [[domain.uitool.injection]] — sources of `STALE_NODE` / precondition errors.
- [[domain.uitool.selector]] — source of `BAD_SELECTOR`; the matcher runs **CLI-side** over the `Capture` the server streams for `find`.

## Notes

- **Exit 6 is precondition-only.** A valid query that matches nothing is **not** an error — it returns **exit 0** with `_meta.totalMatched: 0` (and empty `data`/stream). The agent distinguishes empty-from-error by reading `_meta`, never by the exit code; a 0-match result means _broaden the selector_, not re-issue. (Resolves the HANDOFF §8.1 exit-6 double-assignment: 6 stays precondition-failed only.)
- The per-main-thread-hop timeout is **fixed at ≈500 ms** for v1 (not per-request configurable); a hop that exceeds it returns `TIMEOUT` → exit 7 (HANDOFF §7.4). The wire code is the canonical `TIMEOUT` (the HANDOFF's `MAIN_THREAD_TIMEOUT` working name is collapsed into it — a socket timeout and a main-thread-hop timeout share exit 7 and the one code).
