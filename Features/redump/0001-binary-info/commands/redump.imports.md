---
id: command.redump.imports
kind: command
depends-on: [domain.macho-image]
---

# `redump imports <binary> [--library <name>]`

Imported (undefined) symbols and the dynamic libraries a Mach-O links, read straight from the Mach-O symbol table and load commands via MachOKit — no disassembler.

## Invocation

```
redump imports <binary> [--library <name>]
```

`<binary>` is a path to a thin or universal Mach-O. Imports are read from the **primary slice** (the first slice in file order).

`--library <name>` keeps only imports whose resolved source dylib path **contains** `<name>` as a substring; imports with no resolved library are dropped from a filtered run.

## Output

A JSON array on stdout (deterministic, sorted keys, via `AgentCLI`), one object per imported symbol, in symbol-table order:

```json
[
  { "library": "/usr/lib/libobjc.A.dylib", "name": "_objc_msgSend" },
  { "library": "/usr/lib/swift/libswiftCore.dylib", "name": "_swift_retain" },
  { "name": "_flat_namespace_symbol" }
]
```

- `name` — the imported symbol name exactly as the symbol table records it (leading underscore included). An imported symbol is one whose nlist type is `N_UNDF` (undefined — defined in no section of this image).
- `library` — the path of the dependent dylib the symbol is expected to come from, resolved from the symbol's two-level-namespace library ordinal against the image's `LC_LOAD_DYLIB` (and friends) list. **Omitted** when the ordinal does not name a specific dependency: `SELF_LIBRARY_ORDINAL`, `EXECUTABLE_ORDINAL`, `DYNAMIC_LOOKUP_ORDINAL` (flat-namespace / `-undefined dynamic_lookup`), or an out-of-range ordinal.

## Exit codes

- `0` — imports emitted (an empty array if the binary imports nothing, or if `--library` matched nothing).
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli derives imports from disassembler analysis. `redump imports` reads the Mach-O symbol table and dependent-dylib load commands directly, so it ships in the native half with no licensed tooling.

Per-symbol library resolution depends on the two-level-namespace library ordinal carried in each undefined symbol's nlist description. For ordinary two-level-namespace binaries (the common case on Apple platforms) this resolves each import to a specific dependent dylib. For flat-namespace symbols, self / executable references, and out-of-range ordinals, the source dylib is not determinable from the symbol table alone, so `library` is omitted and only the symbol `name` is reported. The dependent dylibs themselves are always available via the load commands; a future `redump dylibs` slice could surface that list independently.
