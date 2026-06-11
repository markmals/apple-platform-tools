---
id: command.redump.symbols
kind: command
depends-on: [domain.macho-image]
---

# `redump symbols <binary>`

Symbol-table entries read straight from the Mach-O via MachOKit — no disassembler.

## Invocation

```
redump symbols <binary> [--filter <regex>] [--type function|data|all]
```

- `<binary>` is a path to a thin or universal Mach-O. Symbols come from the **primary (first) slice**.
- `--filter <regex>` keeps only symbols whose `name` matches the regular expression (`NSRegularExpression`, matched anywhere in the name).
- `--type` narrows by classification: `function`, `data`, or `all` (the default).

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per symbol in symbol-table order:

```json
[
  { "address": "0x3f1c", "name": "_$s5Probe0aB0V4pingyyF", "type": "function" },
  { "address": "0x8000", "name": "_$s5Probe0aB0VN", "type": "data" },
  { "address": "0x0", "name": "_objc_msgSend" }
]
```

- `address` — the symbol's value (`n_value`), hex-encoded with a `0x` prefix.
- `name` — the raw symbol name from the string table (mangled; not demangled).
- `type` — best-effort classification: `function` when the symbol is defined in a code section, `data` when defined in some other section. **Omitted** when the symbol has no defining section (undefined / absolute symbols), which the native reader cannot classify.

## Classification

`type` is derived from the symbol's defining section, not from disassembly:

- A symbol whose `nlist` type is `N_SECT` and whose section carries instruction attributes (`S_ATTR_PURE_INSTRUCTIONS` / `S_ATTR_SOME_INSTRUCTIONS`), or is `__TEXT,__text`, is a **function**.
- A symbol defined in any other section is **data**.
- A symbol with no defining section (`N_UNDF`, `N_ABS`) has **no `type`**.

`--type all` (the default) never depends on this classification, so it always works. `--type function` and `--type data` partition the section-defined symbols; undefined/absolute symbols (no `type`) fall under `data`.

## Exit codes

- `0` — symbols emitted.
- non-zero — the path is not a readable Mach-O, or `--filter`/`--type` is invalid; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `symbols` derives `function`/`data` from IDA/Hopper analysis. The native reader classifies from the symbol's Mach-O section instead — exact for section-defined symbols, but it cannot label undefined/absolute symbols, so those omit `type`. Names are emitted raw (mangled); demangling is out of scope for the native reader.
