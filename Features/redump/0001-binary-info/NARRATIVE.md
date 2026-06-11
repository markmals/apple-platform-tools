---
id: narrative.redump.binary-info
kind: narrative
---

# redump — reverse-engineering binary inspection

A coding agent investigating a compiled Apple binary needs to understand it without source: what architectures it carries, what kind of Mach-O it is, what symbols and segments it exposes, and — eventually — what its functions disassemble and decompile to. `redump` is the static-analysis cluster's answer, ported from [NSExceptional/re-cli](https://github.com/NSExceptional/re-cli).

re-cli is an end-to-end **IDA Pro / Hopper** orchestrator: every one of its commands runs a Python script inside a disassembler. redump splits that surface in two:

- **Native half (no disassembler, ships first).** A large slice of what an agent asks for is readable straight from the Mach-O via the MachOKit family — the same dependency `headerdump` uses and `BinaryFoundation` wraps: `info` (architectures, file type), and (planned) `segments`, `symbols`, `imports`, `exports`, `strings`, plus `dsc list` over the dyld shared cache. These run anywhere, need no licensed tool, and emit deterministic agent-JSON via `AgentCLI`.
- **Disassembler half (gated, later).** `functions`, `disasm`, `decompile`, `xrefs` genuinely require IDA Pro or Hopper. That backend is a separate, opt-in slice — it can't be built or tested without the (paid) tools installed, so it's deferred and will surface an honest "backend not configured" path.

**Beneficiary:** Mark, reverse-engineering Apple frameworks. **Direct user:** the coding agent, which prefers a single `redump info <binary>` JSON call over spelunking `otool`/`nm` output.

## In scope (this feature)

The `info` command: native binary metadata (path, architectures, file type, bitness) for a thin or universal Mach-O.

## Out of scope (here)

Entry point + address range (re-cli derives these from IDA analysis), and the whole disassembler half. The dyld-shared-cache commands reuse `BinaryFoundation.MachOImage`; they land with the rest of the native half.
