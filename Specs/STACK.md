---
id: stack
kind: stack
---

# Stack

The toolchain catalog for apple-platform-tools — every tool, framework, and service the monorepo wires up. See [ARCHITECTURE.md](ARCHITECTURE.md) for how these fit together and [CONVENTIONS.md](CONVENTIONS.md) for the spec contract.

## Shared spine (every tool)

| Concern | Choice |
| --- | --- |
| Language | [Swift](https://www.swift.org/) 6 (`swift-tools-version` 6.2) |
| Package manager | one [Swift Package Manager](https://www.swift.org/package-manager/) package, many targets |
| Argument parsing | [Swift ArgumentParser](https://github.com/apple/swift-argument-parser) |
| Machine contract | the `AgentCLI` library — deterministic `Codable` JSON, exit-code map, stdout-payload / stderr-diagnostics discipline, `NO_COLOR` |
| Output format | JSON for scalar results; JSON-Lines (one object per line) for streams |
| Subprocess | [swift-subprocess](https://github.com/swiftlang/swift-subprocess) (for tools that shell out — `xcrun`, `simctl`, disassemblers) |
| Tests | [Swift Testing](https://developer.apple.com/xcode/swift-testing/) (XCTest where ObjC `RuntimeKit` is exercised from ObjC) |
| Formatter / linter | [swift-format](https://github.com/swiftlang/swift-format) (`swift format` / `swift format lint --strict`) |
| Specs | Markdown in `Specs/` & `Features/<tool>/`; Gherkin-in-markdown (agent-as-user) |
| Agent instructions | `CLAUDE.md` + `.claude/` |

## Tooling

| Concern | Choice |
| --- | --- |
| Agent | [Claude Code](https://claude.com/product/claude-code) |
| Task runner | [Mise](https://mise.jdx.dev/) — the `fmt` / `lint` / `build` / `test` contract |
| IDE | [Xcode](https://developer.apple.com/xcode/) / [VS Code](https://code.visualstudio.com/) |
| IDE MCP (per-machine, local config) | [Xcode external agent access](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode) |
| CI/CD | [GitHub Actions](https://github.com/Features/actions) — pure-core + oracle/fixture suites only; **never** injection or paid-disassembler runs on shared runners |
| Install | per-tool `codesign` (ad-hoc) + copy to `~/.local/bin`, resource bundles alongside; a root build/sign/install script |

Apple publishes no `/llms.txt` for these frameworks — WebFetch the canonical doc URLs when you need a reference. See the `macos-development` skill for idioms.

## Platforms

| Concern | Choice |
| --- | --- |
| Today | macOS, Apple Silicon. Host-side CLIs that read binaries, SDKs, and other macOS processes. |
| Package floor | the common denominator of the absorbed code; higher-OS features gated per-target with `@available` |
| Runtime preconditions | tool-specific and enforced at runtime, not in the manifest (e.g. `uitool doctor`) |
| Planned | `.iOS` / `.macCatalyst` added to the package when `RuntimeKit`'s Swift UIKit rewrite begins (headless iOS / Catalyst inspection) — not before |

## Cluster: SDK knowledge — `sdk-api`, `sdk-search` (`SDKIndex`)

| Concern | Choice |
| --- | --- |
| Symbol source | `swift symbolgraph-extract` via `xcrun`, cached under `~/Library/Caches`, invalidated on SDK version change |
| Symbol model | SymbolGraph JSON (`identifier.precise`, `availability`, `memberOf` relationships) |
| Search | BM25 with weighted fields + a synonym/stemming pipeline over a curated HIG pattern corpus (embedded `Bundle.module` JSON) |
| Generality | any SDK module via `--module` (AppKit, UIKit, SwiftUI, Foundation, …), not AppKit-only |
| Test oracle | checked-in symbol-graph fixture + corpus-integrity tests — no SDK required at test time |

## Cluster: static binary analysis — `headerdump`, `redump` (`BinaryFoundation`)

| Concern | Choice |
| --- | --- |
| Mach-O parsing | [MachOKit](https://github.com/p-x9/MachOKit) (lynnswap fork) — load commands, segments, sections |
| ObjC metadata | MachOObjCSection — `__objc_*` classes/protocols/categories from static metadata |
| Swift metadata | MachOSwiftSection — `__swift5_*` sections → `.swiftinterface` |
| ObjC dump | swift-objc-dump |
| Runtime fallback | live ObjC runtime (`dlopen`, `objc_copyClassNamesForImage`) when static parse times out |
| Simulator source | `xcrun simctl spawn` + dyld shared cache (`dyld_sim_shared_cache_arm64e`) for iOS framework headers |
| Universal binaries | `lipo`/`file` semantics handled in `BinaryFoundation` |
| `redump` disassembly | drives [IDA](https://hex-rays.com/ida-pro/) (idalib / IDAPython) and [Hopper](https://www.hopperapp.com/) (Python scripting) — **licensed, heavy deps**; the dependency-free half (universal binaries, dyld cache, ObjC metadata) comes from `BinaryFoundation` |
| License note | FLEX-derived code is BSD (dev-only, no App Store); `redump` inherits IDA/Hopper licensing |

## Cluster: live runtime introspection — `uitool` (`RuntimeKit` + `UIToolBoot`)

| Concern | Choice |
| --- | --- |
| Reflection engine | **Swift** reimplementation of FLEX's headless reflection core (mirror / property / ivar / method / protocol / type-encoding parser over `<objc/runtime.h>`), in `RuntimeKit` — the FLEX ObjC is the spec, not the artifact |
| Native floor | `RuntimeKitC` (ObjC/C++) — the ~600 LOC that can't be Swift: pointer-validity probing, Swift-class `isa` decoding, `malloc_zone` heap enumeration |
| View walker | Swift `AppKitWalker` (ported from `FLEXAppKitWalker`) — `NSApp` → `NSWindow` → `NSView`/`CALayer`, frames, `NSFont`/`NSColor` decomposition, constraints → immutable `Sendable` snapshots |
| Frameworks read | [AppKit](https://developer.apple.com/documentation/appkit) · [Core Animation](https://developer.apple.com/documentation/quartzcore) |
| SwiftUI surface | [`NSHostingView`](https://developer.apple.com/documentation/swiftui/nshostingview) (read the emitted AppKit/CALayer scaffold only) |
| Bootstrap | `UIToolBoot` — the one native trigger: an injected ObjC dylib whose `__attribute__((constructor))` `dlopen`s the Swift `UIToolServer` (so the Swift runtime initializes via a normal `dlopen`, not via injection) |
| IPC | Unix domain socket, newline-delimited JSON, versioned schema |
| Concurrency | Swift Concurrency (CLI); GCD main-thread marshaling (server — AppKit reads must run on the target's main thread) |
| Injection | `DYLD_INSERT_LIBRARIES` relaunch (primary); MIP-style `launchservicesd` hook + Mach thread-hijack (first-party, fragile) |
| Preconditions | `uitool doctor` reports **two postures**: **cooperative** (inspect your own `get-task-allow` apps — stock SIP-on Mac, only the arm64 injectable) and **unrestricted** (inspect apps you did NOT sign — `csrutil`, `nvram boot-args` (`amfi_get_out_of_my_way`, `-arm64e_preview_abi`), `DisableLibraryValidation`, arch, the arm64e injectable). The defang is for **non-cooperative targets** only. |
| Signing | `codesign` ad-hoc; the injectable is built **arm64** for cooperative (your own apps) and **arm64e** (`--options runtime`, `disable-library-validation`) to match the system shared cache for unrestricted (apps you did not sign) — **never notarized, never distributed** in either posture |
| Test oracle | `SampleAppKit` (known frames/fonts/constraints) under `DYLD_INSERT_LIBRARIES`; first-party smoke last, dev-box only |
| References | [MIP](https://github.com/LIJI32/MIP) · [yabai loader](https://github.com/koekeishiya/yabai/blob/master/src/osax/loader.m) · [SpecterOps "ARM-ed and Dangerous"](https://specterops.io/blog/2025/08/21/armed-and-dangerous-dylib-injection-on-macos/) |

The runtime cluster weakens the whole machine (SIP + AMFI + LV off) **only for non-cooperative targets** — apps you did not sign — on a dedicated dev box. Inspecting your own `get-task-allow` apps runs on a stock, SIP-enabled Mac. See [ARCHITECTURE.md](ARCHITECTURE.md) → "Dual-use & safety posture" → "Two injection postures".
