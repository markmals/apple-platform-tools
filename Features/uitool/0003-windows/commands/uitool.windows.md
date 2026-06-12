---
id: command.uitool.windows
kind: command
depends-on: [domain.uitool.node, domain.uitool.ipc, domain.uitool.node-id, story.uitool.windows-enumerate]
---

# `uitool windows` — list top-level windows

## Synopsis

```
uitool windows <app> [--pretty] [--no-meta]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target — pid or bundle id, same resolution as every other verb |
| `--pretty` | flag | no | pretty-print JSON; defaults off (machine-first) |
| `--no-meta` | flag | no | suppress the top-level `sessionId` and `_meta` so output is fully byte-stable; defaults off |

## Behavior

1. Resolve `<app>` to the attached session's socket per [[domain.uitool.ipc]]; if no session is attached, fail per [[domain.uitool.ipc]].
2. Issue the [[domain.uitool.ipc]] `hierarchy` op with `maxDepth: 0` and `window: "all"` to the injected server. `maxDepth: 0` projects window roots only — no descendant walk — which is exactly what this verb returns; there is no dedicated `windows` op. The server enumerates the target's top-level windows on the main thread and mints a [[domain.uitool.node-id]] for each window root. The window-enumeration op is the shared `hierarchy` op constrained to `maxDepth: 0` and `window: "all"`; `windows` is a thin CLI verb over it, not a distinct server op — the same op the single-node and tree verbs bind to at their own depths.
3. For each window root, project the window-relevant fields (see Output) and serialize off the main thread.
4. Emit one record per window on stdout.

The set of windows enumerated is the public top-level set: the entries of `NSApp.windows` that are user-facing — ordinary windows and panels (`NSPanel`), including off-screen ones (a window the user has moved off a display, or one positioned but not yet ordered front, is still part of the app's window surface and is reported). Internal and system-owned windows are filtered out: an entry is excluded when it is not a user-facing window — concretely, when `canBecomeKeyWindow` and `canBecomeMainWindow` are both false **and** the window has no title and a zero or off-screen frame (AppKit's hidden helper/utility windows). The NARRATIVE's "off-screen, internal, or system-owned beyond what the contract pins" is pinned here: off-screen user windows are in; internal/system-owned helpers are out.

## Output

JSON-Lines: one window record per line, in `NSApp.windows` array order. That array order is the canonical window sort key — it is the basis for the `wN` window index in [[domain.uitool.node-id]]'s structural path (`w0` is `NSApp.windows[0]`, `w1` is `[1]`, …), so the record order, the node ids, and the structural breadcrumbs all agree. Z-order is **not** the sort key (it is non-deterministic across turns as the user raises and lowers windows); window number is not used either.

Each record is a window-root [[domain.uitool.node]] (so `parent` is `null` at a window root) projected to exactly four base node fields — `node`, `parent`, `class`, `frame` — plus three **window-only** fields not present on a view node: `title`, `key`, and `main`. These three are window-level facts ([[domain.uitool.node]] is a *view* node, which a window root does not have); they are additive fields that appear only on this verb's records and do **not** extend [[domain.uitool.node]]'s field table. The view-relative node fields (`frameTopLeft`, `isFlipped`, `hidden`, `alpha`, `childCount`, etc.) are **not** emitted here: a window root is not enclosed by a view, so they do not apply.

The window `frame` is in **screen coordinates** — `NSWindow.frame` with AppKit's bottom-left screen origin — at 1 dp. Because a window root has no enclosing view, `frameTopLeft` and `isFlipped` do not apply and are omitted (the consumer reads `frame` as screen-space directly; there is no view to flip against).

JSON-Lines, one window record per line on stdout:

```jsonc
{"node":"7:w0","parent":null,"class":"NSWindow","title":"Inbox — Mail","frame":{"x":0,"y":0,"w":1200,"h":800},"key":true,"main":true}
{"node":"7:w1","parent":null,"class":"NSPanel","title":"Find","frame":{"x":1240,"y":120,"w":360,"h":220},"key":false,"main":false}
```

When `--no-meta` is not set, the response also carries the [[domain.uitool.ipc]] envelope on its own trailing line: the mandatory `schemaVersion` (a semver **string**, e.g. `"1.0.0"`, on every payload per [[domain.uitool.ipc]]), a top-level `sessionId` (string), and, for this list verb, `_meta: {returned, truncated, totalMatched}`:

```jsonc
{"schemaVersion":"1.0.0","sessionId":"7","_meta":{"returned":2,"truncated":false,"totalMatched":2}}
```

`--no-meta` strips `sessionId` and `_meta` so output is byte-stable across sessions; `schemaVersion` is **not** suppressible — it is on every payload per [[domain.uitool.ipc]]. An empty window set still exits **0** with `_meta.totalMatched: 0` — it is a valid empty result, never a failure.

## States & exit codes

Exit codes are the [[domain.uitool.ipc]] mapping; the relevant rows:

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (≥ 1 window) | 0 | one record per window on stdout |
| success, no windows open | 0 | empty list + `_meta.totalMatched: 0` on stdout (see [[error.uitool.windows-no-windows]]) |
| usage / bad selector | 2 | structured error on stderr |
| not attached / injection failed | 4 | structured error on stderr (see [[error.uitool.windows-not-attached]]) |
| socket / main-thread timeout | 7 | structured error on stderr (see [[error.uitool.windows-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr |

`windows` is a post-attach query verb: it assumes a live session, so the attach-time codes do not surface here. App-not-running (exit 3) and SIP/AMFI/LV preconditions (exit 6) are attach-time only per [[domain.uitool.ipc]] — an unreachable session surfaces here as **exit 4** (not attached) or **exit 7** (timeout), never 3 or 6. Window enumeration does not deref a caller-supplied node id, so `STALE_NODE` (exit 5) is not reachable from this verb either. Exit 1 is unused here, as in [[domain.uitool.ipc]] — it is reserved by the shell for generic failure.

## Invariants

- Read-only and side-effect-free; idempotent — re-running on an unchanged target yields byte-identical output modulo `sessionId`.
- Deterministic: stable key order, fixed window order, frames at 1 dp, no addresses or timestamps in the default projection.
- An empty window list (exit 0) is distinct from an error (never exit 0 on failure).
- **At most one** record is flagged `key` and **at most one** `main`. When the app is frontmost with a focused window, exactly one record is `key` and exactly one is `main`. But AppKit allows `keyWindow`/`mainWindow` to be `nil` — when the app is backgrounded, or has only non-key-capable panels open, or has no windows — and in that case the verb reports **zero** `key` and/or **zero** `main` rows. The verb never synthesizes a key/main flag to force exactly one; it reports the live AppKit truth. (`key` and `main` are independent: a window can be `main` without being `key`, e.g. while a panel holds key.)
- `parent` is `null` for every record (window roots have no parent), per [[domain.uitool.node]].

## Notes

Cost tier: **cheap / bounded**. This is the cheapest query in the surface — a fixed, tiny payload independent of view-tree size, with no descendant walk. It is the intended first call of a session: list windows, then `tree`/`find` into the chosen one.
