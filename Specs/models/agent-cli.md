---
id: domain.agent-cli
kind: domain
---

# Domain: the AgentCLI contract

The machine contract every tool in this repo obeys, realized as the `AgentCLI` library so honoring it is a dependency, not a memory. This is the through-line that lets one agent drive a symbol-graph query engine and a live process inspector the same way. See `ARCHITECTURE.md` → "The unifying contract".

`AgentCLI` is **pure** (Foundation only — no ArgumentParser, no I/O beyond the explicit stdout/stderr edges). Its projection functions return strings and are unit-tested on any Mac; the printing/exiting functions are the effectful edge.

## Output projection

- **Scalar result → `Output.json(_:)`** — a pretty-printed JSON string with **sorted keys** and **forward slashes unescaped** (`[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`).
- **Stream → `Output.line(_:)`** — one **compact, single-line** JSON object (sorted keys, slashes unescaped) per record; the stream is newline-delimited (JSON-Lines).
- **`Output.emit(_:)` / `Output.emitLines(_:)`** print the above to **stdout** — the machine payload, and nothing else, lands on stdout.

### Determinism invariants

1. **Sorted keys.** Object members are emitted in sorted key order, always.
2. **No slash escaping.** `/` is never written as `\/`.
3. **Byte-identical for equal input.** The same `Encodable` value encodes to the same bytes across runs and processes.
4. **Stable floats.** Floating-point fields are rounded to a fixed number of decimal places (`stableRounded(_:places:)`, default 3) before encoding, so accumulated FP error never changes the bytes.
5. **No volatile fields in the default projection.** No addresses, timestamps, or PIDs unless a verb explicitly asks for them.
6. **JSON-Lines records carry no embedded newline.** Each record is exactly one line.

A consequence: `diff` over two runs is trustworthy, and an agent may cache results by input.

## Exit-code taxonomy

Exit codes are the control channel; a tool never exits `0` on failure, and a zero-result query (no matches) is **success**, distinct from a failure.

- `ExitStatus.success` = **0**
- `ExitStatus.usage` = **2** (a usage/validation error; matches ArgumentParser's validation exit)

Tools extend the space **above 2** with their own meanings via the `AgentError` protocol (e.g. flexscope's `stale-node` = 5, `precondition` = 6, `timeout` = 7). `AgentError` carries:

- `exitCode: Int32` — the code to exit with.
- `message: String` — a human-readable diagnostic, written to **stderr**.

## stdout / stderr discipline

- **stdout** carries the JSON payload alone. No prompts, spinners, progress, color, or pagers — ever.
- **stderr** carries diagnostics: `Diagnostics.warn(_:)` for a non-fatal note, `Diagnostics.fail(_:)` to write an `AgentError`'s message and exit with its code.
- **Color** is off by default and never emitted; `NO_COLOR` is therefore satisfied by construction.

## Acceptance

- `[scenario.agent-cli.sorted-keys]` Object keys encode in sorted order.
- `[scenario.agent-cli.no-escape]` Forward slashes are not escaped.
- `[scenario.agent-cli.deterministic]` Equal input encodes byte-identically.
- `[scenario.agent-cli.jsonlines]` A stream record is one compact object per line, with no embedded newline.
- `[scenario.agent-cli.stable-float]` Float rounding is stable to the requested places.
- `[scenario.agent-cli.exit-taxonomy]` `success` is 0 and `usage` is 2.
