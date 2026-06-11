---
id: narrative.redump.disassembler
kind: narrative
---

# redump's disassembler half

re-cli's full power — `functions`, `disasm`, `decompile`, `xrefs` — comes from driving **IDA Pro** or **Hopper Disassembler**: each command runs a Python script inside the disassembler and normalizes the result to JSON. redump's native half (feature `0001`) covers everything readable straight from the Mach-O; this feature covers the disassembler-backed half.

Those four commands genuinely require a licensed disassembler. That has two consequences for how redump is built:

1. **Detection is native and ships now.** redump can tell — without any disassembler — *which* backends are installed and configured, mirroring re-cli's resolution order (an env override → known install paths → PATH). The `backends` command surfaces that, so an agent (or `mise`/CI) can check readiness before attempting an analysis command. This is the testable foundation.
2. **Driving the disassembler is tools-gated.** The actual `functions`/`disasm`/`decompile`/`xrefs` implementation — composing re-cli's Python scripts, spawning IDA/Hopper, caching the `.i64`/`.hop`, parsing the result envelope — **cannot be built or verified without the paid tools installed.** It is deliberately deferred to a session on a machine that has IDA Pro or Hopper, rather than shipping a large subprocess layer that can't be tested here. The analysis commands resolve a backend via the detector below; when none is configured they fail with a clear, actionable message.

**Beneficiary:** Mark, reverse-engineering on a machine with IDA Pro / Hopper. **Direct user:** the coding agent, which checks `redump backends` and then runs an analysis command.

## In scope (this feature)

The `backends` command and the native backend detection it rests on (env vars `RE_IDAT64` / `RE_HOPPER`, the known Hopper/IDA install locations).

## Out of scope (here, tools-gated)

`functions`, `disasm`, `decompile`, `xrefs` and the IDA/Hopper runner that powers them — tracked for a tools-equipped session.
