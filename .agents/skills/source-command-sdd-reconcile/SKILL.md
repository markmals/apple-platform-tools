---
name: "source-command-sdd-reconcile"
description: "Reconcile a spec with an implementation that drifted ahead of it (inert — single package)."
---

# source-command-sdd-reconcile

Use this skill when the user asks to run the migrated source command `sdd-reconcile`.

## Command Template

# /sdd-reconcile

This command is **inert** in this repo.

Reconciliation existed to propagate one platform's edited implementation back into the spec and out to the *other* platforms. There are no other platforms here: `apple-platform-tools` is one SwiftPM package, and each tool (`sdk-api`, `sdk-search`, `headerdump`, `redump`, `uitool`) and shared library (`AgentCLI`, `MachOFoundation`, `RuntimeKit`, `SDKIndex`) is its own vertical — spec → failing test → implementation. There is no source-of-truth platform to reconcile *from*, and no sibling platform to reconcile *to*.

So the lateral motion this command performed doesn't exist. When an implementation drifts ahead of its spec, the fix is vertical and local:

- The behavior genuinely changed → edit the spec, then `/sdd-apply <spec-id>` to realign the tests and code.
- The implementation was merely made correct against the spec it already had → just fix it and `/sdd-verify`.

The command ships so the harness shape stays uniform, but it does nothing.
