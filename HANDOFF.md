# Apple Platform Tools — Design & Handoff

> The long-form rationale behind the specs. `specs/ARCHITECTURE.md` is the map; this is the territory — why the decisions are what they are, where the code comes from, and the order it lands in. Dated decisions cite the day they were made so a future reader can weigh them against what's changed.

## 1. Vision

A monorepo of Swift packages and CLIs that make a **coding agent** competent at Apple-platform development, with a human steering. Not one app — a toolbox. The bet: Apple-platform work is bottlenecked on *facts an agent can't easily get* — does this symbol exist on this OS, how does Apple's own app achieve a look, what's actually in this private framework, what is this running process's real view tree. Each tool here answers one class of those questions, and they all answer in the same machine-readable shape so the agent learns the box once.

Target surface over time: macOS, iOS, iPadOS, watchOS, tvOS; AppKit, UIKit, SwiftUI, SwiftData, Core Data. The starting tools are macOS-hosted; iOS/Catalyst inspection is a planned expansion of the runtime cluster.

## 2. The unifying idea: one machine contract

Every tool obeys the same contract, captured in code as the **`AgentCLI`** library:

- **stdout is the payload, only the payload.** Deterministic JSON (scalar) or JSON-Lines (streams). Diagnostics → stderr. No prompts/spinners/color/pagers.
- **Exit codes are the control channel.** A documented per-tool map; never `0` on failure; a zero-match query ≠ a failure.
- **Determinism.** Same inputs → byte-identical bytes. Stable keys, fixed-precision floats, no addresses/timestamps/PIDs in the default projection.

This is the reason a symbol-graph query engine and a live process inspector belong in the same repo: an agent that can drive one can drive all of them, diff their output, and cache it. The contract is a dependency (`AgentCLI`), not a convention to remember.

## 3. Prior art absorbed

The monorepo is assembled from existing, mostly-working code. Provenance and state at absorption (2026-06-11):

| Source | Becomes | State at absorption |
| --- | --- | --- |
| `mac-dev-skills/src/tools/appkit-api` | `sdk-api` + `SDKIndex` (symbol half) | **Shipping.** Swift 6, lib+exe split, 10 tests, signed, installed. Symbol-graph extract/index/query; already module-generic via `--module`. |
| `mac-dev-skills/src/tools/appkit-search` | `sdk-search` + `SDKIndex` (search half) | **Shipping.** Swift 6, 44 tests, BM25 + synonym pipeline, embedded 69-pattern HIG corpus. |
| `PrivateHeaderKit` | `headerdump` + `MachOFoundation` | **~90%.** Swift 6.2, ~5.8k LOC, 6 targets. Mach-O `__objc_*`/`__swift*` parsing via MachOKit family + live-runtime fallback; simulator + host dumping. |
| `NSExceptional/re-cli` | `redump` (ported) | **Early** (2 commits). TypeScript wrapper over IDA/Hopper, JSON-for-LLM, universal binaries + dyld cache. To be ported to Swift on `MachOFoundation`. |
| `flexscope` (specs) | `flexscope` + `FlexScopeBoot` | **Specs only.** 72KB HANDOFF, 17 feature folders, domain models. No code. |
| `markmals/FLEX` fork | `RuntimeKit` | **Working ObjC.** 379 files; the headless slice (~4.3k-line reflection core + `FLEXAppKitWalker`, already written in this fork) is what we extract. The iOS GUI is left behind. |

The two `mac-dev-skills` tools and PrivateHeaderKit are real, tested code — the migration is refit-and-verify, not rewrite. flexscope is a complete design with no implementation. The FLEX fork already contains a headless macOS walker; the work is extraction, not authoring.

## 4. Architecture decisions

### 4.1 One SwiftPM package, many targets (2026-06-11)

Chosen over multi-package and over Tuist/Bazel. One `Package.swift` whose internal divide is by *target* — one executable per tool, library targets for the shared foundations. Rationale: one dependency graph, one `swift build`, atomic cross-cutting edits; the per-target boundary still gives each tool and library a clean home that honors the repo's "one responsibility per file" rule.

**Accepted cost:** a single `swift-tools-version` and one platform floor. Mitigation: pin the floor at the common denominator, gate higher-OS features per-target with `@available`, and enforce hard runtime requirements (flexscope's Tahoe + arm64e + defanged machine) at runtime via `doctor` rather than in the manifest. arm64e flags / codesigning / injection are build-script concerns, never baked into a product.

### 4.2 Absorb, don't submodule (2026-06-11)

The four local projects move in as source; the monorepo becomes the single source of truth and the originals are archived. A monorepo's value is shared foundation + atomic cross-cutting change; submodules would reinstate the cross-repo coordination cost it exists to remove. The one extraction: from the FLEX fork we lift only the headless reflection engine + AppKit walker into `RuntimeKit`; the 350-ish files of iOS explorer GUI stay behind. re-cli is ported in regardless of form (it's TypeScript).

### 4.3 Three clusters over two foundations + a contract (2026-06-11)

- **Static binary analysis** (`headerdump`, `redump`) over `MachOFoundation`.
- **Live runtime introspection** (`flexscope`) over `RuntimeKit` (+ `FlexScopeBoot`).
- **SDK knowledge** (`sdk-api`, `sdk-search`) over `SDKIndex`.

All three over `AgentCLI`. Clusters are ordered by cost/danger — SDK knowledge is pure and offline; static analysis spawns subprocesses and reads binaries; runtime introspection injects into a live process on a defanged machine. Agents reach cheapest-first.

### 4.4 The purity boundary, repo-wide (2026-06-11)

Pure logic and I/O never share a function; dependencies point inward. Every tool's decision logic (projection, ranking, grammar, Mach-O structure interpretation) is pure and unit-tested on any Mac with fixtures/corpora; the effectful shell (sockets, injection, subprocess, disassembler, AppKit reads) lives at the edges. The test for a wrong boundary: if a behavior needs injection or a paid disassembler to test, the decision logic wasn't extracted.

## 5. Migration roadmap

Phased so each phase ends green and the riskiest work (injection) is last.

- **Phase 0 — identity + spec spine.** ARCHITECTURE / CONVENTIONS / STACK re-scoped from flexscope to the monorepo; CLAUDE.md + mise re-scoped; this doc. *(in progress)*
- **Phase 0c — harness sweep.** The lifted `.claude/` is flexscope-shaped: commit-discipline scopes name `command.attach`/`flexmac`; the `scoped-commits` hook derives feature scopes from a flat `features/`; `macos-development` describes only flexscope. Re-scope to tool-namespaced scopes, `features/<tool>/` derivation, and a generalized dev skill.
- **Phase 1 — topology + AgentCLI.** Author `Package.swift`'s target graph; build the `AgentCLI` contract library first (it's the through-line). Green build.
- **Phase 1b — first slice.** Migrate `appkit-api` → `sdk-api` and `appkit-search` → `sdk-search` onto `AgentCLI`; factor their cores into `SDKIndex`. **Rename decided (2026-06-11):** generalize to `sdk-*` and update the `mac-dev-skills` skill wiring in the same pass. Tests green via `mise run test`.
- **Phase 2 — static cluster.** Absorb PrivateHeaderKit → `headerdump`; factor Mach-O/dyld reading into `MachOFoundation`. Then port re-cli → `redump` on that foundation, surfacing the IDA/Hopper dependency explicitly.
- **Phase 3 — runtime cluster.** Extract the FLEX headless core → `RuntimeKit`; absorb flexscope's 17-feature spec layer; wire `flexscope` + `FlexScopeBoot` + FLEX-mac within the package; arm64e signing/injection via build script. Develop against the `SampleAppKit` oracle; first-party last.
- **Future — iOS/Catalyst.** Rewrite FLEX's UIKit subsystems in Swift as a headless `RuntimeKit` capability; add `.iOS`/`.macCatalyst` to the package. Enables inspecting iOS apps and Mac Catalyst apps. *(user direction, 2026-06-11)*

## 6. Dual-use & safety posture

These are reverse-engineering instruments used for legitimate Apple-platform development and research. The discipline that keeps them safe:

- **Injection is defanged-machine-only.** `flexscope` needs SIP + AMFI + library-validation off — a system-wide regression, verified at runtime by `doctor`, on a machine holding no real data or credentials. Reversible from Recovery.
- **Containment is a mechanism.** The signed injectable dylib/framework are `.gitignore`d build outputs, never committed, never added to a shippable target or release CI job. A build/commit guard enforces it.
- **Knowledge crosses into products; tools never do.** A font name, a constraint, a header signature, a disassembled routine leaves the repo and informs real work. The injection step does not.
- **Licenses ride with the tools.** FLEX is BSD, dev-only (no App Store); `redump` inherits IDA/Hopper terms.

## 7. Open questions

- **`RuntimeKit` language strategy.** The macOS walker arrives as ObjC; the iOS/Catalyst expansion is slated Swift. Converge the macOS core to Swift too, or keep a stable ObjC reflection engine under a Swift surface? (2026-06-11)
- **`redump` minimum viable surface.** How much of re-cli's value comes from `MachOFoundation` alone (universal binaries, dyld cache, ObjC metadata) before a licensed disassembler is required? Ship the dependency-free half first. (2026-06-11)
- **Install/distribution of the safe tools.** `sdk-api`/`sdk-search`/`headerdump` are harmless and broadly useful — do they get a public install path (Homebrew tap?) while the runtime cluster stays private? (2026-06-11)
- **More tools.** The user has further tool ideas not yet captured here. Each new tool = a new executable target + a `features/<tool>/` namespace; shared capability factors into a foundation. (2026-06-11)
