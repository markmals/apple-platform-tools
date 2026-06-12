# Apple Platform Tools

A monorepo of Swift packages and CLIs that help **coding agents and humans** do
Apple-platform development (macOS, iOS, iPadOS, watchOS, tvOS; AppKit, UIKit,
SwiftUI, SwiftData, Core Data). It is **one SwiftPM package** with many targets:
one executable per tool, library targets for the shared spine, a test target per
unit. Every tool is **agent-first** and obeys one machine contract — deterministic
JSON on stdout, diagnostics on stderr, exit codes as the control channel (the
`AgentCLI` library makes this a dependency, not a memory).

The tools fall into three capability **clusters**, reached cheapest-first — SDK
knowledge (pure, offline) → static binary analysis (reads dead binaries) → live
runtime introspection (injects into a running process). See
[`Specs/ARCHITECTURE.md`](Specs/ARCHITECTURE.md) for the topology and the dual-use
posture, [`Specs/CONVENTIONS.md`](Specs/CONVENTIONS.md) for the spec contract, and
[`Specs/STACK.md`](Specs/STACK.md) for the toolchain.

## Products

The seven things the package vends — five CLIs and two libraries. Four of the CLIs
are built and installed by [`scripts/install-tools.sh`](scripts/install-tools.sh);
`uitool` is **deliberately excluded** — the runtime cluster is dev-box-only and
never distributed (see the dual-use posture):

| Product | Kind | What it does |
| --- | --- | --- |
| `sdk-api` | executable | "Does this SDK symbol exist, and what does it require?" — over Swift symbol graphs. |
| `sdk-search` | executable | "How do I do X?" — ranked HIG / framework pattern search over an embedded corpus. |
| `headerdump` | executable | Private-framework header extraction from Mach-O / the dyld shared cache. |
| `redump` | executable | Reverse-engineering Mach-O inspection (info, segments, symbols, imports/exports, strings). |
| `uitool` | executable *(dev-box-only)* | Inspect a running app's view tree / object graph as JSON. `doctor` / `list-apps` and offline `--snapshot` reads work today; live attach is gated on the injection half. |
| `AgentCLI` | library | The machine contract every tool obeys (deterministic JSON, exit codes, output discipline). |
| `RuntimeKit` | library | A Swift reimplementation of FLEX's headless ObjC-runtime reflection core + AppKit walker. |

Everything else is an **internal** target (a pure core, a foundation, a test, or a
work-in-progress) — not vended as a product.

## Targets by cluster

Twenty-four targets in all. Each library/tool has a Swift Testing target tagged with
the spec IDs it verifies (the `Realizes` column lists the spec contracts a target
implements; see [`Specs/CONVENTIONS.md`](Specs/CONVENTIONS.md)).

### Shared spine — every tool

| Target | Kind | Purpose | Realizes |
| --- | --- | --- | --- |
| `AgentCLI` | library **(product)** | The machine contract as code: key-sorted, slash-unescaped JSON / JSON-Lines, stable float rounding, the exit-code taxonomy, stdout-payload / stderr-diagnostics discipline. No dependencies. | `domain.agent-cli` |
| `TestSupport` | library (test-only, at `Tests/Support`) | The `.spec(_:)` / `.scenario(_:)` association traits shared by **every** test target, carried verbatim so drift/coverage tooling can grep them. | — |
| `AgentCLITests` | test | Proves the contract: sorted keys, unescaped slashes, byte-identical determinism, compact JSON-Lines, stable rounding, exit codes. | `domain.agent-cli` |

### SDK knowledge — `sdk-api`, `sdk-search`

Pure and offline: answers symbol/availability and HIG questions with no target
binary and no network, against checked-in fixtures and an embedded corpus.

| Target | Kind | Purpose | Key dependencies | Realizes |
| --- | --- | --- | --- | --- |
| `SymbolGraphIndex` | library | Extracts and queries Swift symbol graphs for any SDK module (symbol existence, availability). The pure core of `sdk-api`. | `swift-subprocess` (for `xcrun symbolgraph-extract`) | — |
| `sdk-api` | executable **(product)** | Agent-first CLI over symbol graphs, deterministic JSON. | `AgentCLI`, `SymbolGraphIndex`, `swift-argument-parser` | `command.sdk-api.check` · `.members` · `.availability` · `.search` · `.enums` |
| `PatternIndex` | library | BM25 ranked search over an embedded HIG/framework pattern corpus (`Data/patterns.json`, 69 patterns) with a synonym / stop-word / tokenizer pipeline. The pure core of `sdk-search`. | bundled `Data/` resource | — |
| `sdk-search` | executable **(product)** | Agent-first CLI for ranked pattern search, deterministic JSON. | `AgentCLI`, `PatternIndex`, `swift-argument-parser` | `command.sdk-search.search` · `.get` · `.list` · `.debug` |
| `SymbolGraphIndexTests` | test | Pure-first over a checked-in symbol-graph fixture. | `SymbolGraphIndex`, `TestSupport` | `story.sdk-api.symbol-queries` |
| `PatternIndexTests` | test | Pure-first over the embedded corpus (BM25 scoring, tokenization, corpus integrity). | `PatternIndex`, `TestSupport` | `story.sdk-search.pattern-search` |

### Static binary analysis — `headerdump`, `redump`

Reads dead Mach-O binaries and the dyld shared cache on the [MachOKit](https://github.com/p-x9/MachOKit)
family. The pure interpretation logic is unit-tested against checked-in fixtures.

| Target | Kind | Purpose | Key dependencies | Realizes |
| --- | --- | --- | --- | --- |
| `BinaryFoundation` | library | Universal-binary + Mach-O + dyld-shared-cache image loading, env-free with explicit `useSharedCache` / `runtimeRoots`. Shared by `headerdump` and `redump`. | `MachOKit` | `domain.macho-image` |
| `HeaderDumpRuntimeObjC` | ObjC target (`publicHeadersPath: include`, macOS/iOS-gated) | The live ObjC-runtime class-snapshot fallback (`PHRuntimeObjCInspector`) used when static metadata parsing fails. | `objc/runtime`, `Foundation` (system) | — |
| `HeaderDumpCore` | library | Private-framework header extraction via ObjC + Swift section parsing with the runtime fallback. The implementation of `headerdump`. | `BinaryFoundation`, `HeaderDumpRuntimeObjC`, `MachOKit`, `MachOObjCSection`, `ObjCDump`, `MachOSwiftSection`, `SwiftInterface` | `command.headerdump.dump` |
| `headerdump` | executable **(product)** | Thin entry point delegating to `HeaderDumpCore.HeaderDumpCLI.main()`. | `HeaderDumpCore` | — |
| `RedumpCore` | library | Native Mach-O RE inspection — info, segments, symbols, imports, exports, strings, plus disassembler-backend detection. The dependency-free half of `redump`. | `MachOKit` | `command.redump.info` · `.segments` · `.symbols` · `.imports` · `.exports` · `.strings` · `.backends` |
| `redump` | executable **(product)** | The RE CLI — `ArgumentParser` subcommands over `RedumpCore`, AgentCLI-contract JSON. The IDA/Hopper disassembler half stays gated until those tools are installed. | `AgentCLI`, `RedumpCore`, `swift-argument-parser` | `command.redump.*` |
| `BinaryFoundationTests` | test | Mach-O / shared-cache image loading. | `BinaryFoundation`, `TestSupport`, `MachOKit` | `domain.macho-image` |
| `HeaderDumpCLITests` | test | Story-level verification of the framework dump behavior. | `HeaderDumpCore`, `TestSupport`, `HeaderDumpRuntimeObjC`, `MachOKit` | `story.headerdump.dump-framework` |
| `RedumpCoreTests` | test | Per-command unit verification of every `redump` verb. | `RedumpCore`, `TestSupport`, `MachOKit` | `command.redump.*` |

### Live runtime introspection — `uitool` *(CLI live; injection planned)*

Inspects a **running** AppKit/UIKit app — the view hierarchy, fonts, constraints,
the ObjC object graph — by injection on a defanged dev machine. `RuntimeKit` (the
read side), `UIToolCore` (the pure projection core), and the `uitool` CLI are
complete; the injected effectful half (`UIToolServer` / `UIToolBoot`) is planned, so
live attach is gated while `doctor` / `list-apps` / offline `--snapshot` reads work.

| Target | Kind | Purpose | Key dependencies | Realizes |
| --- | --- | --- | --- | --- |
| `RuntimeKit` | library **(product)** | Swift reimplementation of FLEX's headless reflection core + AppKit walker: the type-encoding parser, ObjC-runtime reflection metadata (mirror / property / ivar / method / protocol), and the `NSApp` → `NSView` / `CALayer` walker emitting immutable `Sendable` snapshots. | — | `domain.runtime.type-encoding` · `.reflection` · `.walker` |
| `UIToolCore` | library (internal) | The pure projection core for `uitool`: node model, node-id grammar, Swift-native `Regex` selector + predicate language, tree/find/windows/node projection, the doctor report, and the Capture / IPC-envelope types. Pure and hermetically tested. | `AgentCLI`, `RuntimeKit` | `domain.uitool.node` · `.node-id` · `.selector` · `.ipc` · `command.uitool.*` |
| `uitool` | executable **(product, dev-box-only)** | The agent-first CLI: `doctor` / `list-apps` (real local reads) + `windows` / `tree` / `find` / `node` over a `SnapshotSource` (offline `--snapshot` now, the injected server later); `attach` / `detach` + live reads are gated (`NOT_ATTACHED`). Excluded from `install-tools.sh`. | `AgentCLI`, `UIToolCore`, `RuntimeKit`, `ArgumentParser`, `Subprocess` | `command.uitool.doctor` · `.list-apps` · `.windows` · `.tree` · `.find` · `.node` · `.attach` · `.detach` |
| `RuntimeKitTests` | test | Type-encoding parser, reflection metadata, pointer/tagged-pointer safety, AppKit walker snapshots. | `RuntimeKit`, `TestSupport` | `domain.runtime.*` |
| `UIToolCoreTests` | test | The node/node-id foundation, selector + predicate grammar, and the doctor report against the `uitool` specs (hermetic — synthetic snapshot values, no GUI). | `UIToolCore`, `RuntimeKit`, `TestSupport` | `domain.uitool.*` · `command.uitool.*` |
| `UIToolCLITests` | test | The CLI shell — `Capture` / `SnapshotSource` round-trips, the read verbs over a captured fixture, doctor parsing, and the gated `NOT_ATTACHED` paths. | `uitool`, `UIToolCore`, `RuntimeKit`, `TestSupport` | `command.uitool.*` |

**Planned, not yet targets:** `RuntimeKitC` (the ~600-LOC irreducible native floor —
isa decoding, heap enumeration, pointer-validity probing), `UIToolServer` (the Swift
socket server), and `UIToolBoot` (the injected ObjC bootstrap dylib). The signed
injectable artifacts are `.gitignore`d and never committed.

## External dependencies

| Package | Used by | For |
| --- | --- | --- |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | `sdk-api`, `sdk-search`, `redump` | CLI argument parsing |
| [swift-subprocess](https://github.com/swiftlang/swift-subprocess) | `SymbolGraphIndex` | spawning `xcrun` / `symbolgraph-extract` |
| [MachOKit](https://github.com/lynnswap/MachOKit) (lynnswap fork) | `BinaryFoundation`, `HeaderDumpCore`, `RedumpCore` | Mach-O / dyld-cache / universal-binary parsing |
| [MachOObjCSection](https://github.com/lynnswap/MachOObjCSection) | `HeaderDumpCore` | `__objc_*` class/protocol/category metadata |
| [MachOSwiftSection](https://github.com/lynnswap/MachOSwiftSection) (+ `SwiftInterface`) | `HeaderDumpCore` | `__swift5_*` sections → `.swiftinterface` |
| [swift-objc-dump](https://github.com/p-x9/swift-objc-dump) | `HeaderDumpCore` | ObjC declaration dumping |

## Wiring notes

A few non-obvious facts about the target graph:

- The `*Core` / `*Index` library targets (`SymbolGraphIndex`, `PatternIndex`,
  `BinaryFoundation`, `HeaderDumpCore`, `RedumpCore`) hold each tool's **pure**
  logic and are internal-only; the matching executables are the products. The
  purity boundary — pure logic in, I/O at the edges — is repo-wide.
- `sdk-api`, `sdk-search`, and `redump` declare `AgentCLI` as a **direct**
  dependency; `headerdump` does **not** — it depends only on `HeaderDumpCore`.
- `HeaderDumpRuntimeObjC` is the only ObjC/`publicHeadersPath` target and is gated
  behind `.when(platforms: [.macOS, .iOS])`.
- `PatternIndex` ships a processed `Data/` resource bundle (the HIG corpus);
  `SymbolGraphIndex` is the only target that pulls in `swift-subprocess`.
- `TestSupport` lives at a custom path (`Tests/Support`) and is the shared
  dependency of every test target.

## Building

```sh
swift build                       # build everything
swift test                        # run all Swift Testing suites
mise run fmt | lint | build | test  # the task contract (swift-format + the above)
scripts/install-tools.sh          # codesign + install the CLIs to ~/.local/bin
```

## Where to read more

| Question | File |
| --- | --- |
| Architecture, the three clusters, the dual-use posture | [`Specs/ARCHITECTURE.md`](Specs/ARCHITECTURE.md) |
| The spec contract — IDs, frontmatter, reverse pointers, drift | [`Specs/CONVENTIONS.md`](Specs/CONVENTIONS.md) |
| The toolchain catalog (per tool) | [`Specs/STACK.md`](Specs/STACK.md) |
| The full design rationale | [`HANDOFF.md`](HANDOFF.md) |
| How an agent should work in this repo | [`CLAUDE.md`](CLAUDE.md) |
