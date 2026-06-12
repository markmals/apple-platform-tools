---
id: narrative.headerdump.dump-framework
kind: narrative
---

# Dumping a framework's real private headers

## Who this is for

A coding agent (steered by a macOS or iOS developer) that needs to understand or
call into a private or system framework Apple ships **without** public headers —
a SPI on `AppKit`, an undocumented class in a `/System/Library/PrivateFrameworks`
bundle, a simulator-only runtime framework.

## The situation today

When a framework has no published `.h` or `.swiftinterface`, the agent is
flying blind: it guesses at selectors from stale training data, invents method
signatures that don't exist, or gives up on the API entirely. The real
declarations *are* present — encoded in the Mach-O image's Objective-C and Swift
metadata sections — but the agent has no way to read them. The class list, the
ivars, the method type encodings, the protocol conformances, the Swift type and
protocol descriptors are all sitting in `__objc_*` and `__swift5_*` sections (or
in the running Objective-C runtime), and there is no public tool that turns them
back into headers the agent can read.

## What we're building

`headerdump` reconstructs a framework's private API surface as **header files**.
It parses the Mach-O image's Objective-C and Swift metadata statically (via the
MachOKit family — `MachOObjCSection`, `MachOSwiftSection`, `ObjCDump`,
`SwiftInterface`) and emits one `.h` per Objective-C class, protocol, and
category, plus a `.swiftinterface` per Swift module. When the static parser
can't reach a symbol — or is pathologically slow on a large framework in a
modern dyld shared cache — it falls back to the **live Objective-C runtime**,
which is a complete substitute for class metadata. It can read images straight
out of the **dyld shared cache** (the only place most system frameworks' bytes
live on a modern OS), and it can resolve framework bundles inside a simulator
runtime root. Point it at a file, a `.framework`/`.app`/`.bundle`, or — with
`-r` — a whole directory tree, and it writes the recovered headers to an output
directory.

## Why this matters

The agent reads the *real* API — actual selectors, actual ivars, actual Swift
signatures — instead of hallucinating one. The private surface Apple doesn't
publish becomes a directory of headers the agent can grep, cite, and call
against, recovered offline from bytes already on the machine.

## What this is NOT

- Not a symbol *existence* check — that is `sdk-api`. This tool recovers full
  declarations; it does not answer "does `X` exist on macOS 26?".
- Not a live-process inspector — it reads images on disk (or in the shared
  cache), not the AppKit object graph of a running app. That is `uitool`.
- Not a disassembler — it recovers declarations from metadata, not function
  bodies from instructions.
- Not (today) an agent-JSON query tool. Its output is header *files*, not a
  deterministic JSON projection on stdout — see `command.headerdump.dump`.
