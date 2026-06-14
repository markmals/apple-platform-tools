---
id: error.uitool.attach-schema-mismatch
kind: error
depends-on: [domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Schema version mismatch

## When this happens

The channel opened and the handshake completed, but the injected server reports a different protocol/schema version than the CLI expects — the separately-built CLI and dylib have desynced ([[domain.uitool.ipc]]: the `ping` handshake is what keeps them from desyncing).

## What the user sees

Exit code 8 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"SCHEMA_MISMATCH","message":"CLI expects schemaVersion \"1.0.0\", server reports \"2.0.0\"","recover":"rebuild UIToolBoot.dylib (and UIToolServer) from the same source as the CLI"}}`

The wire `error.code` for the version mismatch is `SCHEMA_MISMATCH` (exit 8) — canonical.

## What the user can do

- Rebuild [[domain.uitool.boot]] and [[domain.uitool.server]] from the same source as the CLI so both carry the same `schemaVersion`, then re-attach or re-launch.

## Underlying cause (informational)

- The `v` / `schemaVersion` carried in the `ping` response does not match the CLI's expected version ([[domain.uitool.ipc]]); only additive changes within a major are compatible.

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[domain.uitool.ipc]] — the schema handshake and version invariant.
