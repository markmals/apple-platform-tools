---
id: architecture
kind: architecture
---

# Architecture

> Orientation, not exhaustive reference. The full design rationale lives in `HANDOFF.md`; per-tool, per-capability detail lives in the feature folders under `Features/<tool>/`. This document is the map.

## Product overview

**apple-platform-tools** is a monorepo of Swift packages and CLIs that help **coding agents and humans** do Apple-platform development — macOS, iOS, iPadOS, watchOS, tvOS, and the frameworks on top (AppKit, UIKit, SwiftUI, SwiftData, Core Data). It is not one app; it is a **toolbox** with a shared spine.

Every tool here is **agent-first**: the primary consumer is an LLM, and the human steering it is the ultimate beneficiary. That single design commitment is what unifies tools as different as a symbol-graph query engine and a live runtime inspector — they all speak the same machine contract (below), so an agent learns the shape once and reuses it across the whole box.

## The unifying contract (every tool obeys this)

This is the through-line. A tool earns a place in this repo by honoring it:

- **stdout is the machine payload, and only that.** Deterministic JSON for scalar results; JSON-Lines (one object per line) for streams. Diagnostics, progress, and warnings go to **stderr**. No prompts, spinners, color, or pagers — ever. `NO_COLOR` is respected, but color is off by default regardless.
- **Exit codes are the control channel.** `0` success, `2` usage error, and a documented per-tool map beyond that. Never exit `0` on failure; a zero-match query is distinct from a failed one.
- **Determinism.** Same inputs → byte-identical bytes. Stable key order, fixed-precision floats, no addresses/timestamps/PIDs in the default projection. `diff` is trustworthy; the agent can cache.
- **Knowledge in, knowledge out.** These tools surface facts about a binary, an SDK, or a running process. The fact is the deliverable.

The contract lives in code as the **`AgentCLI`** library (see *Shared foundations*), so honoring it is a dependency, not a memory.

## Topology — one package, many targets

**A single SwiftPM package at the repo root, with one executable target per tool and library targets factored by responsibility.** (Decision: 2026-06-11.) Not a workspace of separate packages — one `Package.swift` whose internal divide is by *target*, giving each tool and each shared library a clean boundary while keeping one dependency graph, one `swift build`, and atomic cross-cutting edits.

```
apple-platform-tools/            ← one SwiftPM package
  Package.swift
  Sources/
    # ── shared foundations (libraries) ──────────────────────────
    AgentCLI/          the machine contract: Codable JSON, exit-code map, output discipline
    BinaryFoundation/   Mach-O + dyld-shared-cache + universal-binary reading (MachOKit family)
    RuntimeKit/        headless ObjC-runtime reflection + AppKit walker (extracted FLEX core)
    SymbolGraphIndex/  Swift symbol-graph extraction + query (any SDK module)
    PatternIndex/      BM25 search over an embedded framework/HIG pattern corpus
    # ── tools (executables) ─────────────────────────────────────
    sdk-api/           SDK symbol existence + availability        (← appkit-api)
    sdk-search/        ranked HIG/framework pattern search          (← appkit-search)
    headerdump/        private framework header extraction          (← PrivateHeaderKit)
    redump/            disassembler wrapper (IDA/Hopper) → agent-JSON (← re-cli, ported)
    flexscope/         live AppKit view-tree inspector (injection)  (← flexscope)
    FlexScopeBoot/     injected ObjC bootstrap dylib                (flexscope's server host)
  Tests/
  Specs/                         ← cross-cutting specs (this file, CONVENTIONS, STACK)
  Features/<tool>/<NNNN>-<slug>/  ← feature-scoped specs, namespaced by tool
```

**The cost of one package, named honestly:** a single `swift-tools-version` and one platform floor for the whole graph. We pin the floor at the common denominator and gate higher-OS features per-target with `@available`. Tools with hard *runtime* requirements (flexscope needs Tahoe + arm64e + a defanged machine) enforce those at runtime via a `doctor` verb, not via the package manifest. arm64e build flags, codesigning, and injection are **build-script** concerns, never baked into a shippable product.

## The three capability clusters

| Cluster | Tools | Shared foundation | What it answers |
| --- | --- | --- | --- |
| **Static binary analysis** | `headerdump`, `redump` | `BinaryFoundation` | "What's *in* this binary?" — classes, protocols, headers, disassembly, from Mach-O / the dyld shared cache, without running it. |
| **Live runtime introspection** | `flexscope` | `RuntimeKit` (+ `FlexScopeBoot`) | "What is this *running* process actually doing?" — real view-tree, fonts, constraints, ivars, via injection + the ObjC runtime. |
| **SDK knowledge** | `sdk-api`, `sdk-search` | `SymbolGraphIndex`, `PatternIndex` | "Does this symbol exist / what does it require / how do I do X?" — symbol graphs + a curated HIG pattern corpus. No target binary or process needed. |

Cheapest cluster (SDK knowledge — pure, offline, any Mac) to most dangerous (runtime introspection — injection, defanged machine). An agent should reach left-to-right: answer from SDK knowledge if it can, drop to static analysis if it must, and only attach to a live process when nothing else will do.

## Shared foundations (the leverage)

The whole point of the monorepo is that the expensive parts are written once:

- **`AgentCLI`** — the machine contract as code. Deterministic `Codable` JSON encoder (stable keys, fixed-precision floats), the exit-code taxonomy, stdout/stderr discipline, `NO_COLOR`. **Every executable links this.** Built first (Phase 1) precisely because it's the contract.
- **`BinaryFoundation`** — universal-binary + Mach-O + dyld-shared-cache image loading, on MachOKit. Its `MachOImage` namespace (`load`/`loadFromSharedCache`/`sharedCachePath`/`normalizedCacheImagePaths`) was factored out of `HeaderDumpCore`'s seam in Phase 2a, decoupled from headerdump's `DumpOptions` and the process environment into explicit `useSharedCache` / `runtimeRoots` parameters — so the library is env-free and the tool reads the dyld runtime roots at its own edge. Shared by `headerdump` and (later) `redump`. (Named `BinaryFoundation`, not `MachOFoundation`, because the MachOKit package already ships a module by that name. Spec: `domain.macho-image`. 2026-06-11.)
- **`RuntimeKit`** — the **headless** slice of FLEX: its ObjC reflection engine (`FLEXMirror`/`FLEXProperty`/`FLEXIvar`/`FLEXMethod`, `FLEXRuntimeUtility`), the heap enumerator, and the `FLEXAppKitWalker`. The ~4,300-line core that needs no UI. The FLEX explorer GUI is left behind. **Future direction:** the iOS/UIKit subsystems get rewritten in Swift and brought in headless, so `RuntimeKit` can inspect iOS apps and Mac Catalyst apps — not just AppKit. (User direction, 2026-06-11.)
- **`SymbolGraphIndex`** — Swift symbol-graph extraction + query for any SDK module (from `appkit-api`'s `AppKitAPICore`, generalized past AppKit). Powers `sdk-api`.
- **`PatternIndex`** — the BM25 engine + embedded framework/HIG pattern corpus (from `appkit-search`'s `AppKitSearchCore`). Powers `sdk-search`. (The single `SDKIndex` foundation named at design time split into these two focused libraries during Phase 1b — symbol-graph querying and corpus search are separate responsibilities, and neither tool should link the other's code. 2026-06-11.)

## The purity boundary (the most consequential structural rule)

Lifted from flexscope and applied repo-wide: **pure logic and I/O do not share a function, and dependencies point inward.**

- **Pure core** (no I/O, deterministic, unit-testable on any Mac, no privileges): JSON projection, exit-code mapping, the node-ID / selector grammars, symbol-graph indexing and ranking, Mach-O *structure* interpretation once bytes are in hand.
- **Effectful shell** (pushed to the edges): the socket and injection (flexscope), `xcrun`/`simctl`/subprocess spawns (`headerdump`, `sdk-api`), driving IDA/Hopper (`redump`), reading the live system state `doctor` inspects, every AppKit read (which **must** run on the target's main thread).

If a behavior needs injection, a simulator, or a paid disassembler to test, the boundary was drawn wrong — extract the decision logic into the pure core and feed it captured fixtures. The working tools already do this (checked-in symbol-graph fixtures, an embedded corpus); the rule generalizes.

## Platforms

**macOS today.** The tools are host-side CLIs that read binaries, SDKs, and other macOS processes. The package floor sits at the common denominator of the absorbed code; per-tool higher-OS needs are gated with `@available`, and flexscope's Tahoe/arm64e/defanged-machine requirement is a **runtime** precondition (`flexscope doctor`), not a manifest constraint.

**iOS / iPadOS / Mac Catalyst are a planned `RuntimeKit` expansion**, not a current target. When the Swift rewrite of FLEX's UIKit core begins, `.iOS` / `.macCatalyst` get added to the package and that capability ships headless. We do not declare those platforms before there is code that needs them (YAGNI).

## Dual-use & safety posture

Several tools here are reverse-engineering instruments — private-header extraction, disassembler wrapping, dyld-cache dumping, and live code injection. They are legitimate for Apple-platform development and research, and this repo treats them that way. The discipline:

- **The injection tool is defanged-machine-only.** `flexscope` requires SIP + AMFI + library-validation off — a system-wide regression. That machine holds no real data or credentials. This is verified at runtime by `flexscope doctor`, documented once, and never softened.
- **Containment is a mechanism, not a memory.** The signed injectable dylib / framework are an attack tool elsewhere. They are `.gitignore`d build outputs, never committed, never added to a shippable target or a release CI job. A build/commit guard enforces this.
- **Knowledge crosses into products; tools never do.** A font name, a constraint, a header signature, a disassembled routine — that's what leaves this repo and informs real work. The injection step does not.
- **The static-analysis tools carry their sources' license terms.** FLEX is BSD but forbids App Store use (dev-only); `redump` inherits IDA/Hopper licensing. These ride along with the tools, not around them.

## Spec discipline (how work lands here)

This repo is spec-driven. Specs in `Specs/` (cross-cutting) and `Features/<tool>/<NNNN>-<slug>/` (feature-scoped, **namespaced by tool** — the multi-tool generalization of flexscope's flat numbering) are the source of truth; the implementation carries `// SPEC: <id>` reverse pointers back. Each tool is its own **vertical** (spec → failing test → implementation → review → verification). There is no cross-platform projection to reconcile, so the lateral SDD machinery (`/sdd-reconcile`) stays inert; the vertical is fully in force. See `CONVENTIONS.md` for the contract and `STACK.md` for the toolchain.

## Open architectural questions

- **Binary naming for the SDK-knowledge tools** — keep `appkit-api` / `appkit-search`, or generalize the names to `sdk-api` / `sdk-search` to match the generalized `SDKIndex`? The existing names are load-bearing in the `mac-dev-skills` skill wiring; a rename needs a coordinated update there. (2026-06-11)
- **`RuntimeKit` language strategy** — the macOS walker arrives as ObjC (the existing FLEX-mac code); the iOS/Catalyst expansion is slated as a Swift rewrite. Do we converge the macOS core to Swift too, or keep a stable ObjC reflection engine under a Swift surface? (2026-06-11)
- **`redump` minimum viable surface** — IDA (idalib/IDAPython) and Hopper are both heavy, licensed dependencies. How much of re-cli's value is recoverable from `BinaryFoundation` alone (universal binaries, dyld cache, ObjC metadata) before a disassembler is required? (2026-06-11)
