---
id: error.uitool.windows-no-windows
kind: error
depends-on: [domain.uitool.ipc, command.uitool.windows]
---

# No top-level windows open

## When this happens

The agent is attached to a running target that currently has no top-level windows open (e.g. a menu-bar-only app, or an app whose windows are all closed). This is a successful query with an empty result, **not** a failure — but it is a distinct, user-observable outcome the agent must not mistake for an error or retry blindly.

## What the user sees

An empty window list on stdout (no record lines) and exit code **0** per [[domain.uitool.ipc]]. The empty result is explicitly marked by the [[domain.uitool.ipc]] envelope's `_meta.totalMatched: 0` so it cannot be confused with a truncated read or a crash. With the envelope present (i.e. without `--no-meta`), the full top-level response carries the mandatory `schemaVersion` and the top-level `sessionId` alongside `_meta`:

> `{"schemaVersion":"1.0.0","sessionId":"7","_meta":{"returned":0,"truncated":false,"totalMatched":0}}`
>
> With `--no-meta`, `sessionId` and `_meta` are stripped and only `schemaVersion` remains; stdout carries no record lines either way.

## What the user can do

- **Accept the empty result** — re-issuing the identical query is the wrong recovery; the answer will not change until the app opens a window.
- **Bring up a window** — drive the app to open a window (open a document, trigger its main window), then re-run.

## Underlying cause (informational)

- The enumerated top-level window set (`NSApp.windows`, filtered per [[command.uitool.windows]]) is empty.

## Related

- [[command.uitool.windows]] — the verb that surfaces this.
- [[story.uitool.windows-enumerate]] — scenario `scenario.uitool.windows-enumerate.empty`.
- [[domain.uitool.ipc]] — empty-success is distinct from failure (never exit 0 on failure, and never non-zero on a valid empty result).
