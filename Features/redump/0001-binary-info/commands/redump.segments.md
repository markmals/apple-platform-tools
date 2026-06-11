---
id: command.redump.segments
kind: command
depends-on: [domain.macho-image]
---

# `redump segments <binary>`

The Mach-O's segments, read straight from their load commands via MachOKit — no disassembler.

## Invocation

```
redump segments <binary>
```

`<binary>` is a path to a thin or universal Mach-O. Segments are read from the **first slice** (the primary one); a universal binary reports the first architecture's segments.

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one entry per segment in **load order**:

```json
[
  { "name": "__TEXT", "start": "0x100000000", "end": "0x100004000" },
  { "name": "__DATA", "start": "0x100004000", "end": "0x100008000" }
]
```

- `name` — the segment name (`__TEXT`, `__DATA`, `__LINKEDIT`, `__PAGEZERO`, …).
- `start` — the segment's unslid virtual address (`vmaddr`), hex-encoded with a `0x` prefix.
- `end` — `vmaddr + vmsize`, hex-encoded with a `0x` prefix.

## Exit codes

- `0` — segments emitted (the array may be empty for a segment-less object file).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `segments` carries an optional `type` field (a segment classification derived from IDA/Hopper analysis). The native reader has no clean source for it, so `type` is **omitted** rather than guessed. Like `redump info`, a failure surfaces as ArgumentParser's generic non-zero exit rather than a per-tool `AgentError` code. [NEEDS CLARIFICATION: surface `type` once the disassembler backend lands, and adopt `AgentError` exit codes once redump grows commands with distinct failure modes?]
