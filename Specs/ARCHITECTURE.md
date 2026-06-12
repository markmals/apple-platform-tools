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
    RuntimeKitC/       irreducible native floor: pointer-validity / Swift-class isa decode / heap walk (ObjC/C++)
    RuntimeKit/        Swift reflection (over <objc/runtime.h>) + AppKit walker — a Swift reimplementation of FLEX's headless core
    UIToolCore/     pure Swift: node model, node-id + selector grammars, projection, JSON-Lines, exit codes
    UIToolServer/   Swift headless server: socket + main-thread marshaling + node registry
    SymbolGraphIndex/  Swift symbol-graph extraction + query (any SDK module)
    PatternIndex/      BM25 search over an embedded framework/HIG pattern corpus
    # ── tools (executables) ─────────────────────────────────────
    sdk-api/           SDK symbol existence + availability        (← appkit-api)
    sdk-search/        ranked HIG/framework pattern search          (← appkit-search)
    headerdump/        private framework header extraction          (← PrivateHeaderKit)
    redump/            disassembler wrapper (IDA/Hopper) → agent-JSON (← re-cli, ported)
    uitool/         live AppKit view-tree inspector (injection)  (← uitool)
    UIToolBoot/     injected ObjC bootstrap dylib                (uitool's server host)
  Tests/
  Specs/                         ← cross-cutting specs (this file, CONVENTIONS, STACK)
  Features/<tool>/<NNNN>-<slug>/  ← feature-scoped specs, namespaced by tool
```

**The cost of one package, named honestly:** a single `swift-tools-version` and one platform floor for the whole graph. We pin the floor at the common denominator and gate higher-OS features per-target with `@available`. Tools with hard *runtime* requirements (uitool needs Tahoe + arm64e + — for **non-cooperative targets** — a defanged machine) enforce those at runtime via a `doctor` verb, not via the package manifest. arm64e build flags, codesigning, and injection are **build-script** concerns, never baked into a shippable product.

## The three capability clusters

| Cluster | Tools | Shared foundation | What it answers |
| --- | --- | --- | --- |
| **Static binary analysis** | `headerdump`, `redump` | `BinaryFoundation` | "What's *in* this binary?" — classes, protocols, headers, disassembly, from Mach-O / the dyld shared cache, without running it. |
| **Live runtime introspection** | `uitool` | `RuntimeKit` (+ `UIToolBoot`) | "What is this *running* process actually doing?" — real view-tree, fonts, constraints, ivars, via injection + the ObjC runtime. Your own get-task-allow apps inspect on a stock Mac; only apps you did not sign need the defanged box. |
| **SDK knowledge** | `sdk-api`, `sdk-search` | `SymbolGraphIndex`, `PatternIndex` | "Does this symbol exist / what does it require / how do I do X?" — symbol graphs + a curated HIG pattern corpus. No target binary or process needed. |

Cheapest cluster (SDK knowledge — pure, offline, any Mac) to most dangerous (runtime introspection — injection). An agent should reach left-to-right: answer from SDK knowledge if it can, drop to static analysis if it must, and only attach to a live process when nothing else will do. Within that last cluster, the cost itself has two tiers — inspecting **your own get-task-allow apps** runs on a stock, SIP-enabled Mac (the cooperative posture); only **apps you did not sign** (system / notarized) need the defanged machine (the unrestricted posture). See "Two injection postures" under *Dual-use & safety posture*.

## Shared foundations (the leverage)

The whole point of the monorepo is that the expensive parts are written once:

- **`AgentCLI`** — the machine contract as code. Deterministic `Codable` JSON encoder (stable keys, fixed-precision floats), the exit-code taxonomy, stdout/stderr discipline, `NO_COLOR`. **Every executable links this.** Built first (Phase 1) precisely because it's the contract.
- **`BinaryFoundation`** — universal-binary + Mach-O + dyld-shared-cache image loading, on MachOKit. Its `MachOImage` namespace (`load`/`loadFromSharedCache`/`sharedCachePath`/`normalizedCacheImagePaths`) was factored out of `HeaderDumpCore`'s seam in Phase 2a, decoupled from headerdump's `DumpOptions` and the process environment into explicit `useSharedCache` / `runtimeRoots` parameters — so the library is env-free and the tool reads the dyld runtime roots at its own edge. Shared by `headerdump` and (later) `redump`. (Named `BinaryFoundation`, not `MachOFoundation`, because the MachOKit package already ships a module by that name. Spec: `domain.macho-image`. 2026-06-11.)
- **`RuntimeKit`** — a **Swift reimplementation** of FLEX's headless reflection core and AppKit walker. The ObjC runtime (`<objc/runtime.h>`) and AppKit are both fully Swift-callable, so the reflection metadata layer (mirror/property/ivar/method/protocol over the runtime), the type-encoding parser, and the entire walker (view tree, fonts, constraints, layers, SwiftUI-boundary detection) are Swift, emitting immutable `Sendable` snapshots. Resting on **`RuntimeKitC`** — the ~600-LOC irreducible native floor that genuinely can't be Swift: pointer-validity / tagged-pointer probing, Swift-class `isa` decoding (private `objc_class` bits, `.mm`), and heap enumeration (held-lock `malloc_zone` C callbacks). The FLEX ObjC source is the **spec, not the artifact** — it's ported, not vendored. The FLEX explorer GUI is left behind. **Future direction:** the iOS/UIKit walker is a further Swift expansion, so `RuntimeKit` can inspect iOS apps and Mac Catalyst apps. (Resolves Q2; user direction, 2026-06-11.)
- **`SymbolGraphIndex`** — Swift symbol-graph extraction + query for any SDK module (from `appkit-api`'s `AppKitAPICore`, generalized past AppKit). Powers `sdk-api`.
- **`PatternIndex`** — the BM25 engine + embedded framework/HIG pattern corpus (from `appkit-search`'s `AppKitSearchCore`). Powers `sdk-search`. (The single `SDKIndex` foundation named at design time split into these two focused libraries during Phase 1b — symbol-graph querying and corpus search are separate responsibilities, and neither tool should link the other's code. 2026-06-11.)

## The purity boundary (the most consequential structural rule)

Lifted from uitool and applied repo-wide: **pure logic and I/O do not share a function, and dependencies point inward.**

- **Pure core** (no I/O, deterministic, unit-testable on any Mac, no privileges): JSON projection, exit-code mapping, the node-ID / selector grammars, symbol-graph indexing and ranking, Mach-O *structure* interpretation once bytes are in hand.
- **Effectful shell** (pushed to the edges): the socket and injection (uitool), `xcrun`/`simctl`/subprocess spawns (`headerdump`, `sdk-api`), driving IDA/Hopper (`redump`), reading the live system state `doctor` inspects, every AppKit read (which **must** run on the target's main thread).

If a behavior needs injection, a simulator, or a paid disassembler to test, the boundary was drawn wrong — extract the decision logic into the pure core and feed it captured fixtures. The working tools already do this (checked-in symbol-graph fixtures, an embedded corpus); the rule generalizes.

## Platforms

**macOS today.** The tools are host-side CLIs that read binaries, SDKs, and other macOS processes. The package floor sits at the common denominator of the absorbed code; per-tool higher-OS needs are gated with `@available`, and uitool's Tahoe/arm64e requirement (plus, **for non-cooperative targets — apps you did not sign**, the defanged machine) is a **runtime** precondition (`uitool doctor`), not a manifest constraint.

**iOS / iPadOS / Mac Catalyst are a planned `RuntimeKit` expansion**, not a current target. When the Swift rewrite of FLEX's UIKit core begins, `.iOS` / `.macCatalyst` get added to the package and that capability ships headless. We do not declare those platforms before there is code that needs them (YAGNI).

## Dual-use & safety posture

Several tools here are reverse-engineering instruments — private-header extraction, disassembler wrapping, dyld-cache dumping, and live code injection. They are legitimate for Apple-platform development and research, and this repo treats them that way. The discipline:

- **The defanged machine is required only for non-cooperative targets.** macOS gates injection **per target**, and which gate applies depends on who controls the target's code signing. For apps **you build and sign for development** (a debug build carries `get-task-allow` — the entitlement by which the app opts in to being debugged/injected), `uitool` runs on a **stock, SIP-enabled Mac** with no machine-wide changes — exactly how lldb / Xcode / Reveal attach to your own apps. The system-wide defang (SIP + AMFI + library-validation off — a system-wide regression) is required **only to inspect apps you did NOT sign** (system / notarized), which ship hardened with no per-app lever to flip. That defanged machine holds no real data or credentials and is reversible from Recovery. Both postures are verified at runtime by `uitool doctor`, which reports each independently.
- **Containment is a mechanism, not a memory.** The signed injectable dylib / framework are an attack tool elsewhere. They are `.gitignore`d build outputs, never committed, never added to a shippable target or a release CI job. A build/commit guard enforces this — and it holds in **both** postures: the cooperative path needs no machine defanging, but the signed injectable is still never distributed.
- **Knowledge crosses into products; tools never do.** A font name, a constraint, a header signature, a disassembled routine — that's what leaves this repo and informs real work. The injection step does not.
- **The static-analysis tools carry their sources' license terms.** FLEX is BSD but forbids App Store use (dev-only); `redump` inherits IDA/Hopper licensing. These ride along with the tools, not around them.

### Two injection postures

macOS gates injection **per target**; which gate applies depends on who controls the target's code signing. `uitool` therefore runs in one of two postures, and `uitool doctor` reports both so an agent knows what it can attach to from here:

- **Cooperative** (the default dev loop; SIP / AMFI / library-validation stay **on**). Target: an app **you build and sign** for development. A debug build is signed with `get-task-allow` (Xcode's default) — the entitlement by which the app *opts in* to being debugged/injected — and either runs without the hardened runtime or carries the dyld-environment + disable-library-validation entitlements; you control all of this because it is your build. SIP's debugging restriction only protects Apple-signed restricted processes, so a `get-task-allow` target is honored regardless of SIP. **Machine requirements: none beyond the OS** — no `csrutil`, no boot-args, no reboot. The injectable just needs to be built **arm64** (a normal Xcode app is arm64, so the injectable matches). The per-target preconditions — the target is debuggable and, for the launch path, permits dyld env vars — are checked at attach, not by the machine doctor.
- **Unrestricted** (arbitrary / system / notarized targets; the defanged dev box). Target: any app, **including ones you did not sign** — Mail, Finder, a notarized third-party app. These ship hardened with no `get-task-allow`, so there is no per-app lever; the only path is to lower the protections **machine-wide** (SIP off, `amfi_get_out_of_my_way=0x1`, library validation disabled, `-arm64e_preview_abi`, and the injectable built **arm64e** to match the arm64e system shared cache). This is the full defang stack the doctor's unrestricted checks cover. A dedicated dev box that holds no real data; reversible from Recovery.

The reframe: the defanged machine is the **worst case, not the floor**. For your own apps, `uitool` is a stock-Mac tool. The injection half (`UIToolBoot` / `UIToolServer`) is not built yet, so neither posture is usable *today* — but the cooperative path's only gap is that (deferred) dylib, not a missing machine defang.

## Spec discipline (how work lands here)

This repo is spec-driven. Specs in `Specs/` (cross-cutting) and `Features/<tool>/<NNNN>-<slug>/` (feature-scoped, **namespaced by tool** — the multi-tool generalization of uitool's flat numbering) are the source of truth; the implementation carries `// SPEC: <id>` reverse pointers back. Each tool is its own **vertical** (spec → failing test → implementation → review → verification). There is no cross-platform projection to reconcile, so the lateral SDD machinery (`/sdd-reconcile`) stays inert; the vertical is fully in force. See `CONVENTIONS.md` for the contract and `STACK.md` for the toolchain.

## Resolved architectural decisions

- **`uitool` has two injection postures — cooperative and unrestricted** → macOS gates injection per target, by who controls the target's code signing. **Cooperative** (the default dev loop) inspects apps you build and sign (`get-task-allow`) on a **stock, SIP-enabled Mac** — no machine-wide changes, only the arm64 injectable. **Unrestricted** inspects apps you did NOT sign (system / notarized) and needs the full machine defang (SIP + AMFI + LV off, `-arm64e_preview_abi`, the arm64e injectable) on a dedicated dev box. The defanged machine is the worst case, not the floor: the tool was previously documented as if every target were hostile. `uitool doctor` reports **both** postures; exit 0 when the cooperative posture is usable, else 6. Containment is unchanged — the signed injectable is never distributed in either posture. (Resolved 2026-06-12.)
- **Binary naming for the SDK-knowledge tools** → **`sdk-api` / `sdk-search`** (generalized past AppKit), with the `mac-dev-skills` skill wiring updated in the same pass. (Resolved 2026-06-11.)
- **`RuntimeKit` language strategy** → **Swift-first.** Convert FLEX's headless core to Swift over a ~600-LOC irreducible native floor (`RuntimeKitC`: pointer-validity probing, Swift-class isa decoding, heap enumeration) plus the injectable `UIToolBoot` constructor. The FLEX ObjC is the spec, not the artifact. The runtime cluster splits into `RuntimeKitC` (native floor) + `RuntimeKit` (Swift reflection + walker) + `UIToolCore` (pure Swift node/selector/JSON core) + `UIToolServer` (Swift socket server) + `UIToolBoot` (native boot dylib) + `uitool` (Swift CLI). (Resolves Q2, 2026-06-11.)
- **`redump` minimum viable surface** → ship the **dependency-free half on `BinaryFoundation`** first (info/segments/symbols/imports/exports/strings, native — done); the IDA/Hopper disassembler half stays gated until the tools are installed. (Resolved 2026-06-11.)
- **The live-runtime tool's name** → **`uitool`** (Apple-systems-tool style, in the `otool` / `vmmap` lineage), replacing the prior-art `flexscope` branding it no longer wears; core library `UIToolCore`, boot `UIToolBoot`, server `UIToolServer`, namespace `Features/uitool/`. (Resolved 2026-06-11.)
- **`UIToolCore` foundational clarifications** → resolved the pure core's open `[NEEDS CLARIFICATION]` markers so the public API can be locked: selector/predicate matching is **Swift-native `Regex`** (case-insensitive, unanchored substring; an invalid pattern throws → `BAD_SELECTOR`); `find`/`classes` carry a **`--limit 50` default + `--count-only`** ("size it before you pay"); a malformed projection splits into **distinct** codes — `UNKNOWN_FIELD` (bad `--fields` path) vs `BAD_PREDICATE` (malformed `--where`), both exit 2. Scope locked to the **cheap-read MVP** (node model + selector grammar + tree/find/windows/node projection + JSON-Lines/exit contract); the getter-invoking verbs (ivars/props/classes/ax-diff/swiftui) and the injection half are deferred. (Resolved 2026-06-11.)

## Open architectural questions

- **`uitool` expensive-verb + injection clarifications** — the deferred getter-invoking verbs (ivars/props value-boxing, classes filters/ordering, ax-diff's AX source, swiftui probe) and the IPC/error-code wire vocabulary still carry `[NEEDS CLARIFICATION]` in the absorbed specs. Resolve via `/sdd-clarify` when those verbs and the injection half are built — not needed for the cheap-read `UIToolCore`. (2026-06-11)
