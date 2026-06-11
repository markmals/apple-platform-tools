---
id: command.redump.exports
kind: command
depends-on: [domain.macho-image]
---

# `redump exports <binary>`

Exported symbols read straight from the Mach-O export trie via MachOKit — no disassembler.

## Invocation

```
redump exports <binary>
```

`<binary>` is a path to a thin or universal Mach-O. Exports are read from the **primary slice** (the first slice in file order).

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per exported symbol, in export-trie order:

```json
[
  { "address": "0x3f40", "name": "_$s5Probe05probeA15ExportedFunctionyyF" },
  { "name": "_$s5ProbeAAVMn" }
]
```

- `name` — the exported symbol name exactly as the trie records it (leading underscore included).
- `address` — the symbol's offset from the start of the file, as a `0x`-prefixed hex string. **Omitted** when the trie carries no offset for the symbol (re-exports, absolute symbols).

## Exit codes

- `0` — exports emitted (an empty array if the binary exports nothing).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli derives exports from disassembler analysis. `redump exports` reads the Mach-O export trie directly, so it ships in the native half with no licensed tooling. It reports the symbol's file **offset** as `address`; the trie does not carry a runtime VM address, so no IDA/Hopper-style absolute address is synthesized.
