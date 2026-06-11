---
id: command.redump.backends
kind: command
---

# `redump backends`

Report which disassembler backends (IDA Pro / Hopper) are configured for redump's analysis commands. Native — needs no disassembler to run.

## Invocation

```
redump backends
```

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one entry per backend:

```json
[
  { "backend": "ida",    "configured": false, "path": null },
  { "backend": "hopper", "configured": true,  "path": "/Applications/Hopper.app/Contents/MacOS/hopper" }
]
```

- `backend` — `ida` or `hopper`.
- `configured` — whether the tool was located.
- `path` — the resolved tool path, or `null`.

## Resolution order

For each backend, redump checks (mirroring re-cli):

1. An environment override — `RE_IDAT64` (IDA's `idat64`) or `RE_HOPPER` (Hopper's executable).
2. Known install locations — `/Applications/IDA Pro/idabin/idat64`; the `Hopper Disassembler[ v4/v5].app` / `Hopper.app` bundles.

(re-cli additionally globs `/Applications` for versioned IDA installs and falls back to `which`; those effectful steps are out of scope for the pure resolver.)

## Exit codes

- `0` — statuses emitted.

## Relationship to the analysis commands

`functions`, `disasm`, `decompile`, and `xrefs` consume this detection: each resolves a backend and, when none is `configured`, fails with an actionable message. Their implementation (driving IDA/Hopper) is tools-gated and tracked separately — see `narrative.redump.disassembler`.
