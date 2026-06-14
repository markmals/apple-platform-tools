# Apple Platform Tools — Design & Handoff

> The long-form rationale behind the specs. `Specs/ARCHITECTURE.md` is the map; this is the territory — why the decisions are what they are, where the code comes from, and the order it lands in. Dated decisions cite the day they were made so a future reader can weigh them against what's changed.

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
| `PrivateHeaderKit` | `headerdump` + `BinaryFoundation` | **~90%.** Swift 6.2, ~5.8k LOC, 6 targets. Mach-O `__objc_*`/`__swift*` parsing via MachOKit family + live-runtime fallback; simulator + host dumping. |
| `NSExceptional/re-cli` | `redump` (ported) | **Early** (2 commits). TypeScript wrapper over IDA/Hopper, JSON-for-LLM, universal binaries + dyld cache. To be ported to Swift on `BinaryFoundation`. |
| `flexscope` (specs) | `uitool` + `UIToolBoot` | **Specs only.** 72KB HANDOFF, 17 feature folders, domain models. No code. Absorbed as the `uitool` tool (renamed 2026-06-11). |
| `markmals/FLEX` fork | `RuntimeKit` | **Working ObjC.** 379 files; the headless slice (~4.3k-line reflection core + `FLEXAppKitWalker`, already written in this fork) is what we extract. The iOS GUI is left behind. |

The two `mac-dev-skills` tools and PrivateHeaderKit are real, tested code — the migration is refit-and-verify, not rewrite. flexscope is a complete design with no implementation. The FLEX fork already contains a headless macOS walker; the work is extraction, not authoring.

## 4. Architecture decisions

### 4.1 One SwiftPM package, many targets (2026-06-11)

Chosen over multi-package and over Tuist/Bazel. One `Package.swift` whose internal divide is by *target* — one executable per tool, library targets for the shared foundations. Rationale: one dependency graph, one `swift build`, atomic cross-cutting edits; the per-target boundary still gives each tool and library a clean home that honors the repo's "one responsibility per file" rule.

**Accepted cost:** a single `swift-tools-version` and one platform floor. Mitigation: pin the floor at the common denominator, gate higher-OS features per-target with `@available`, and enforce hard runtime requirements (uitool's Tahoe + arm64e, plus the defanged machine **only for non-cooperative targets** — apps you did not sign) at runtime via `doctor` rather than in the manifest. arm64e flags / codesigning / injection are build-script concerns, never baked into a product.

### 4.2 Absorb, don't submodule (2026-06-11)

The four local projects move in as source; the monorepo becomes the single source of truth and the originals are archived. A monorepo's value is shared foundation + atomic cross-cutting change; submodules would reinstate the cross-repo coordination cost it exists to remove. The one extraction: from the FLEX fork we lift only the headless reflection engine + AppKit walker into `RuntimeKit`; the 350-ish files of iOS explorer GUI stay behind. re-cli is ported in regardless of form (it's TypeScript).

### 4.3 Three clusters over two foundations + a contract (2026-06-11)

- **Static binary analysis** (`headerdump`, `redump`) over `BinaryFoundation`.
- **Live runtime introspection** (`uitool`) over `RuntimeKit` (+ `UIToolBoot`).
- **SDK knowledge** (`sdk-api`, `sdk-search`) over `SDKIndex`.

All three over `AgentCLI`. Clusters are ordered by cost/danger — SDK knowledge is pure and offline; static analysis spawns subprocesses and reads binaries; runtime introspection injects into a live process (on a stock Mac for your own `get-task-allow` apps; on a defanged machine only for apps you did not sign). Agents reach cheapest-first.

### 4.4 The purity boundary, repo-wide (2026-06-11)

Pure logic and I/O never share a function; dependencies point inward. Every tool's decision logic (projection, ranking, grammar, Mach-O structure interpretation) is pure and unit-tested on any Mac with fixtures/corpora; the effectful shell (sockets, injection, subprocess, disassembler, AppKit reads) lives at the edges. The test for a wrong boundary: if a behavior needs injection or a paid disassembler to test, the decision logic wasn't extracted.

### 4.5 Cooperative vs unrestricted injection postures (Resolved 2026-06-12)

**macOS gates injection per *target*, not per *machine*.** This is the insight that reshapes the runtime cluster's safety story, and it's recorded in `Specs/ARCHITECTURE.md` (Resolved 2026-06-12).

- **Cooperative** (the default dev loop). An app **you build and sign** for development carries `get-task-allow` — the opt-in to being debugged/injected. With that lever set, the target is injectable on a **stock, SIP-enabled Mac** with SIP / AMFI / library-validation **all on** — exactly how lldb / Xcode / Reveal attach to your own apps. It needs only a debuggable target and the **arm64** `UIToolBoot` dylib; the v1 mechanism is a `DYLD_INSERT_LIBRARIES` launch. No machine-wide changes.
- **Unrestricted**. An app you did **not** sign (system / notarized) ships hardened with no per-app lever, so reaching it needs the full machine defang — SIP + AMFI + library-validation off, `-arm64e_preview_abi`, the arm64e injectable — on a dedicated dev box.

`uitool doctor` reports **both** postures and exits on the **cooperative** verdict (0 when the cooperative posture is usable, else 6). The defanged box is the worst case, not the floor. This decision is what lets the cheap-read live MVP target a stock Mac rather than presupposing a wiped dev box.

## 5. Migration roadmap

Phased so each phase ends green and the riskiest work (injection) is last.

- **Phase 0 — identity + spec spine. ✅ done.** ARCHITECTURE / CONVENTIONS / STACK re-scoped from flexscope to the monorepo; CLAUDE.md + mise re-scoped; this doc. Identity flip complete — "many tools, one package," not "one tool."
- **Phase 0c — harness sweep. ✅ done.** The lifted `.claude/` was flexscope-shaped (commit-discipline scopes named `command.attach`/`flexmac`; `scoped-commits` derived from a flat `Features/`; `macos-development` described only flexscope). Re-scoped to tool-namespaced scopes, `Features/<tool>/` derivation, and a generalized dev skill.
- **Phase 1 — topology + AgentCLI. ✅ done.** `Package.swift`'s target graph authored; `AgentCLI` (the JSON / exit-code / output-discipline contract) built first as the through-line. Green build.
- **Phase 1b — first slice. ✅ done.** `appkit-api` → `sdk-api` and `appkit-search` → `sdk-search` migrated onto `AgentCLI`; their cores factored into `SymbolGraphIndex` + `PatternIndex` (the SDK foundation split in two). Suite moved to trait-based test tagging. Tests green via `mise run test`.
- **Phase 2 — static cluster. ✅ done.** PrivateHeaderKit absorbed → `headerdump`; Mach-O/dyld reading factored into `BinaryFoundation` (on MachOKit). re-cli ported → `redump` on that foundation: `info` / `segments` / `symbols` / `imports` / `exports` / `strings` native, plus disassembler-backend detection (`backends`) surfacing the IDA/Hopper dependency explicitly. Both tools installed.
- **Phase 3 — runtime cluster. ◐ READ side done; injection half remains.** **Done:** the FLEX headless core extracted → `RuntimeKit` (type-encoding parser → reflection metadata → headless AppKit walker); `UIToolCore`, the pure projection core (node model, node-id grammar, Swift-Regex selector/predicate, tree/find/windows/node verbs, projection, doctor report, Capture + IPC-envelope types); the `uitool` CLI (agent-first, over `UIToolCore`); the flexscope → uitool rename; the cheap-read spec layer absorbed (`Features/uitool/0001-0006` + the 5 `domain.uitool.*` models); and **the injection-posture reframe** — cooperative vs unrestricted (2026-06-12), so uitool runs on a stock Mac against your own apps. **The injection half is now fully specified (2026-06-14)** and is the open edge to implement: the inject-and-walk-a-foreign-process path — `UIToolBoot` (the boot dylib, `domain.uitool.boot`) + `UIToolServer` (the in-target socket server over the existing `RuntimeKit.AppKitWalker`, `domain.uitool.server`) + the IPC transport + the `SampleAppKit` known-geometry oracle. **v1 scope decision (2026-06-14):** the cooperative posture ships **both** mechanisms — `uitool launch` (spawn-inject under `DYLD_INSERT`, clean state) *and* `uitool attach` (task-port `task_for_pid` + remote `dlopen`, attach-to-running, **preserves live state**); the *unrestricted* running-attach into a target you did **not** sign (the `launchservicesd` hook, M5) stays deferred. Specs added/reconciled this pass: new `domain.uitool.{server,boot}`, new `command.uitool.launch` + `story.uitool.launch` + `error.uitool.launch-not-found`, and reconciled `domain.uitool.injection` (un-defer cooperative attach-to-running), `domain.uitool.ipc` (the `data` payload is a server-produced `Capture`), `command.uitool.attach` (attach-to-running only; `--relaunch` removed → it's `launch`), the attach-inject/attach-release stories, and the shared attach error catalog. The pure core and the cooperative *read* path are complete. **The cooperative injection half is now built and verified end-to-end on a stock arm64 Mac (2026-06-14).** Layers, all green: `UIToolBoot` (ObjC `+load` shim → `@_cdecl` Swift entry → starts the server, a dynamic library DYLD_INSERTed/remote-dlopened); `SampleAppKitApp` (the launchable oracle); the `UIToolIPC` socket transport (both ends — `SocketServer` accept loop, `IPCClient`, the bounded main-thread hop); `UIToolServer`'s forest-shipping bridge; `uitool launch` (`posix_spawn` under `DYLD_INSERT`, stdio redirected); `uitool attach` (`UIToolInject` — `task_for_pid` + a bootstrap mach thread that `pthread_create_from_mach_thread` → `dlopen`s the dylib; **arm64 only, no PAC**; needs `uitool` signed with `com.apple.security.cs.debugger`); `uitool detach` (a transport-control op); and `doctor` now reporting the real injectable presence. Verified: `launch`/`attach` a target → `windows`/`tree`/`find`/`node` read it live; `detach` → `NOT_ATTACHED`; attach preserves the running app's state. The earlier v1 limits are **fixed (2026-06-14):** re-attach after detach now restarts the server (the boot keys on the socket's presence, and the injector `dlsym`+calls `uitool_boot_start` since `+load` won't refire on a resident dylib), and `mise run uitool-sign` handles the attach debugger-entitlement signing. **What remains:** the *unrestricted* posture (system/notarized targets — the SIP/AMFI defang + arm64e/PAC injection, the deferred hard sub-project) and Phase 3.5's expensive verbs.
- **Phase 3.5 — expensive verbs + the native floor. ◐ inspect built (2026-06-14).** The scope turned out narrower than billed: **fonts / layer / constraints are already live** — the walker captures them and `node`/`tree`/`find --include` expose them over the socket. The one genuinely-new value-fetching verb, **`inspect`, is now built and verified by real injection**: `command.uitool.inspect` + `domain.uitool.registry` (the node-id → live-object resolver; v1 re-walks the live tree, the weak map is the deferred optimization) + `ObjectInspector` (reads ivar *values* — the part `RuntimeKit` deliberately omitted — via `object_getIvar`/offset memory reads, screened by `RuntimeSafety`) + the gated `--invoke` getter path over **`RuntimeKitC`** (the native safety floor's first piece — an ObjC `@try/@catch` shim). Verified: `inspect --invoke` a live `NSVisualEffectView` reads its `material` (7) and the target survives. **What remains of 3.5:** the other flexscope verbs (classes, ax-diff, swiftui, schema, signing) and the rest of `RuntimeKitC`'s native floor (pointer-validity probing, Swift-class isa decode, heap enumeration) — each still a `/sdd-clarify` + scope call.
- **Future — iOS/Catalyst.** Rewrite FLEX's UIKit subsystems in Swift as a headless `RuntimeKit` capability; add `.iOS`/`.macCatalyst` to the package. Enables inspecting iOS apps and Mac Catalyst apps. *(user direction, 2026-06-11)*

## 6. Dual-use & safety posture

These are reverse-engineering instruments used for legitimate Apple-platform development and research. The discipline that keeps them safe:

- **The defanged machine is for non-cooperative targets only.** macOS gates injection per target. For apps **you build and sign** for development (a debug build carries `get-task-allow` — the opt-in to being debugged/injected), `uitool` runs on a **stock, SIP-enabled Mac** with no machine-wide changes, exactly as lldb/Xcode attach to your own apps; it needs only the arm64 injectable built. The system-wide defang — SIP + AMFI + library-validation off, a system-wide regression on a box holding no real data, reversible from Recovery — is required **only to inspect apps you did not sign** (system / notarized), which ship hardened with no per-app lever. `doctor` reports both postures at runtime.
- **Containment is a mechanism.** The signed injectable dylib/framework are `.gitignore`d build outputs, never committed, never added to a shippable target or release CI job. A build/commit guard enforces it.
- **Knowledge crosses into products; tools never do.** A font name, a constraint, a header signature, a disassembled routine leaves the repo and informs real work. The injection step does not.
- **Licenses ride with the tools.** FLEX is BSD, dev-only (no App Store); `redump` inherits IDA/Hopper terms.

## 7. Open questions

- **`RuntimeKit` language strategy.** The macOS walker arrives as ObjC; the iOS/Catalyst expansion is slated Swift. Converge the macOS core to Swift too, or keep a stable ObjC reflection engine under a Swift surface? (2026-06-11)
- **`redump` minimum viable surface.** How much of re-cli's value comes from `BinaryFoundation` alone (universal binaries, dyld cache, ObjC metadata) before a licensed disassembler is required? Ship the dependency-free half first. (2026-06-11)
- **Install/distribution of the safe tools.** `sdk-api`/`sdk-search`/`headerdump` are harmless and broadly useful — do they get a public install path (Homebrew tap?) while the runtime cluster stays private? (2026-06-11)
- **More tools.** The user has further tool ideas not yet captured here. Each new tool = a new executable target + a `Features/<tool>/` namespace; shared capability factors into a foundation. (2026-06-11)
