---
id: command.redump.strings
kind: command
depends-on: [domain.macho-image]
---

# `redump strings <binary>`

C strings read straight from the Mach-O's `__TEXT,__cstring` section via MachOKit — no disassembler.

## Invocation

```
redump strings <binary> [--min-length <n>] [--filter <regex>]
```

`<binary>` is a path to a thin or universal Mach-O. Strings are read from the **primary slice** (the first slice in file order).

- `--min-length <n>` — drop strings shorter than `n` characters. Default `4`.
- `--filter <regex>` — keep only strings whose value matches the regular expression.

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per C string, in section order:

```json
[
  { "address": "0x100003f40", "value": "REDUMP_MARKER_STRING" },
  { "address": "0x100003f55", "value": "%s: %d\n" }
]
```

- `value` — the NUL-terminated C string, decoded as UTF-8. MachOKit walks the section and splits it on NUL; each entry carries its offset within the section.
- `address` — the string's unslid virtual address: the `__TEXT,__cstring` section's `vmaddr` plus the string's offset within the section, as a `0x`-prefixed hex string.

A slice with no `__TEXT,__cstring` section yields an empty array.

## Exit codes

- `0` — strings emitted (an empty array if the binary has no `__TEXT,__cstring` section, or none survive the filters).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `strings` enumerates strings discovered across the binary by disassembler analysis. `redump strings` reads the `__TEXT,__cstring` section directly, so it ships in the native half with no licensed tooling. `address` is the string's **virtual address** (section `vmaddr` + in-section offset), not a disassembler-resolved cross-reference. Only `__TEXT,__cstring` is read — UTF-16 (`__ustring`) and strings embedded in other sections are out of scope for the native reader.
