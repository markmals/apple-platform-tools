---
id: command.redump.info
kind: command
depends-on: [domain.macho-image]
---

# `redump info <binary>`

Native binary metadata read straight from the Mach-O via MachOKit — no disassembler.

## Invocation

```
redump info <binary>
```

`<binary>` is a path to a thin or universal Mach-O.

## Output

A single JSON object on stdout (deterministic, sorted keys, via `AgentCLI`):

```json
{
  "path": "<binary>",
  "archs": ["arm64", "x86_64"],
  "fileType": "dylib",
  "bitness": 64
}
```

- `archs` — every Mach-O slice's architecture name (`arm64`, `arm64_32`, `arm`, `x86_64`, `i386`, `ppc`, `ppc64`, else the raw case), in file order. One entry for a thin binary; several for a universal one.
- `fileType` — the Mach-O filetype of the first slice: `object`, `execute`, `dylib`, `bundle`, `dylinker`, `dylib-stub`, `dsym`, `kext`, `core`, `preload`, `fileset`, `fvmlib`, else the raw case.
- `bitness` — `64` for `arm64`/`x86_64`/`ppc64`, else `32`, from the first slice.

## Exit codes

- `0` — info emitted.
- non-zero — the path is not a readable Mach-O; a diagnostic is written to stderr and no JSON is written to stdout.

## Deviations from re-cli

re-cli's `info` also returns `entry`, `minAddress`, and `maxAddress`, which it derives from IDA/Hopper analysis. Those require the disassembler backend and are **not** part of the native reader. `redump info` deliberately departs from the per-tool `AgentError` exit-code map for now: a failure surfaces as ArgumentParser's generic non-zero exit, which is sufficient for a single-error command. [NEEDS CLARIFICATION: adopt `AgentError` exit codes once redump grows commands with distinct failure modes?]
