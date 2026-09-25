---
name: macos-development
description: Use when writing or modifying Swift/ObjC code anywhere in apple-platform-tools — the ArgumentParser CLIs over the AgentCLI contract, the shared foundations (MachOFoundation, SDKIndex, RuntimeKit), and the runtime cluster's injected ObjC bootstrap dylib + AppKit walker. Covers Swift 6 + ArgumentParser, deterministic JSON output, Swift/ObjC interop, Swift Testing, and — for the runtime cluster only — AppKit/Core Animation introspection, main-thread marshaling, and arm64e codesigning. Complementary to `implementing-a-spec` (process) and `test-driven-development`.
---

# macOS / Swift Development

How to write this repo's code. For the _workflow_ of implementing a spec, see `implementing-a-spec`. For _what_ to build, read the spec and `Specs/ARCHITECTURE.md`.

apple-platform-tools is **one SwiftPM package, many targets**. Most tools are pure Swift CLIs that link `AgentCLI` and a foundation. The runtime cluster (`uitool`) adds ObjC and injection. The shape by target:

- **A tool** (`sdk-api`, `sdk-search`, `headerdump`, `redump`, `uitool`) — an `executableTarget`: an ArgumentParser CLI that parses args, calls the shell (subprocess / RPC / injection / a foundation API), and hands the result to the pure `AgentCLI` encoder.
- **A foundation** (`AgentCLI`, `MachOFoundation`, `SDKIndex`, `RuntimeKit`) — a library `target`: the expensive, reusable logic, written once and unit-tested in isolation.
- **`UIToolBoot`** — the injected ObjC bootstrap dylib for the runtime cluster; a `__attribute__((constructor))` starts a headless server. ObjC, arm64e, signed by the build script, never committed.

## Stack at a glance

| Concern | Choice | First-party docs |
| --- | --- | --- |
| Language (CLIs + foundations) | Swift 6 (`swift-tools-version` 6.2) | [docs.swift.org/swift-book](https://docs.swift.org/swift-book/) |
| Argument parser | Swift ArgumentParser | [github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) |
| Machine contract | the `AgentCLI` library | `Specs/models/agent-cli.md` |
| Subprocess | swift-subprocess (for `xcrun`/`simctl`/disassembler spawns) | [github.com/swiftlang/swift-subprocess](https://github.com/swiftlang/swift-subprocess) |
| Language (runtime cluster dylib + walker) | Objective-C / C | [Programming with Objective-C](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/) |
| Runtime introspection (runtime cluster) | `<objc/runtime.h>` + the FLEX reflection engine in `RuntimeKit` | [objc runtime](https://developer.apple.com/documentation/objectivec/objective-c_runtime) |
| Views read (runtime cluster) | AppKit + Core Animation | [appkit](https://developer.apple.com/documentation/appkit) · [quartzcore](https://developer.apple.com/documentation/quartzcore) |
| Tests | Swift Testing | [swift-testing](https://developer.apple.com/xcode/swift-testing/) |
| Formatter / linter | swift-format | [github.com/swiftlang/swift-format](https://github.com/swiftlang/swift-format) |
| Package manager | SwiftPM | [swift.org/package-manager](https://www.swift.org/package-manager/) |
| Signing (runtime cluster) | `codesign` (ad-hoc, arm64e), `otool` / `lipo` | [code signing](https://developer.apple.com/documentation/security/code-signing-services) |

Apple publishes no `/llms.txt` — WebFetch the canonical URLs when you need a reference.

## The AgentCLI contract (every tool)

The through-line. A command is thin and machine-first; the deterministic JSON, exit codes, and stdout/stderr discipline come from `AgentCLI` so they're a dependency, not a memory. See `Specs/models/agent-cli.md`.

```swift
// SPEC: command.sdk-api.check
import AgentCLI
import ArgumentParser

struct Check: AsyncParsableCommand {
    @Argument var symbol: String
    @Option(name: .customLong("module")) var module = "AppKit"

    func run() async throws {
        let result = try await SymbolIndex.shared.check(symbol, in: module)  // shell / foundation
        try Output.emit(result)                                              // pure encode → stdout
    }
}
```

- **stdout is the machine payload only.** `Output.emit` (scalar) / `Output.emitLines` (JSON-Lines stream). Diagnostics, progress, warnings → stderr via `Diagnostics.warn`. No prompts, spinners, color, or pagers — ever.
- **Exit codes are the control channel.** `ExitStatus.success` (0), `ExitStatus.usage` (2), and a per-tool `AgentError` above 2. `Diagnostics.fail(error)` writes the message to stderr and exits with its code. Never exit 0 on failure; a 0-match query is success, distinct from a failure.
- **Output is deterministic.** `Output.json`/`.line` sort keys and don't escape slashes; round floats with `stableRounded` before encoding. Same inputs → byte-identical bytes, so `diff` is trustworthy and the agent can cache.
- Keep the command body a few lines: call the shell, hand the result to the pure encoder.

## The purity boundary (write to it)

`Specs/ARCHITECTURE.md` defines this; honoring it is what makes each tool testable without its effectful dependency.

- **Pure core** (Swift, no I/O, deterministic): JSON projection, exit-code mapping, ranking/grammars, Mach-O *structure* interpretation once bytes are in hand, the view-snapshot model + node-ID derivation. Unit-test these on any Mac.
- **Effectful shell** (push to the edges): subprocess spawns, sockets, process injection, the disassembler, every AppKit read, reading live system state.

If a behavior needs injection, a simulator, or a paid disassembler to test, the boundary was drawn wrong — extract the decision logic into the pure core and feed it captured fixtures.

## ObjC ↔ Swift interop (runtime cluster)

`RuntimeKit`'s reflection engine and walker, and the `UIToolBoot` server, are ObjC (they touch the runtime and AppKit on the target's main thread). A Swift CLI talks to them **only over the socket** — it does not link AppKit reads directly. Bridge ObjC into Swift via the target's umbrella header; keep the seam narrow.

## AppKit introspection — you are *reading*, never building (runtime cluster)

The four traps that make wrong frames instead of crashes (so they're silent — assert against the oracle):

- **Real class:** `NSStringFromClass(object_getClass(view))` — the actual private subclass, the whole point vs AX. (`-class` can lie under KVO; use `object_getClass`.)
- **Coordinate flip:** AppKit is bottom-left origin and `isFlipped` varies per view. Emit raw `frame` **and** a normalized top-left window-relative rect **and** `isFlipped`.
- **Nil layers:** `NSView.layer` is nil unless `wantsLayer`. Walk the view tree for structure; attach `CALayer` data only where present. Emit the layer tree as a parallel structure cross-linked by node id.
- **Color resolution:** resolve `NSColor` via the window's `effectiveAppearance` + `usingColorSpace:` before reading components; catalog/dynamic colors throw otherwise. Report the appearance context.

### Main-thread marshaling is load-bearing

All AppKit reads run on the **target's** main thread; the socket loop is off-main. Off-main AppKit access crashes the *target*. Snapshot quickly on main into an immutable model, serialize JSON off-main, and bound every hop:

```objc
// SPEC: domain.ipc
static id RunOnMain(NSTimeInterval timeout, id (^block)(void)) {
    __block id result = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{ result = block(); dispatch_semaphore_signal(sem); });
    long late = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    return late ? nil : result;  // nil → MAIN_THREAD_TIMEOUT, never a hang
}
```

### arm64e + signing

Build the injectable dylib **arm64e** (a plain-arm64 dylib fails dyld with "missing compatible architecture" — a silent failure `doctor` must surface). Ad-hoc sign every artifact (`codesign --force --sign - --options runtime …`); the dylib/framework carry `com.apple.security.cs.disable-library-validation`. Verify with `lipo -archs`, `file`, `codesign -dv`. The build/sign script does this idempotently and stamps "never distribute". Never notarize, never distribute, never commit the signed artifact.

## Tests at the pure-core layer, oracle for the rest

```swift
import TestSupport
import Testing
@testable import AgentCLI

@Suite(.spec("domain.agent-cli"))
struct OutputTests {
    @Test(.scenario("scenario.agent-cli.sorted-keys"))
    func `object keys are emitted in sorted order`() throws { /* ... */ }
}
```

- The `.spec("<id>")` trait carries the spec ID; the `.scenario("<id>")` trait pins the Gherkin scenario; the function name is a raw identifier — its natural-language text *is* the test name. Both traits live in the shared `TestSupport` target. Drift tooling greps `.spec("…")` / `.scenario("…")` (Swift), and the `// SPEC:` / `// [scenario.<id>]` comment form for RuntimeKit's ObjC/XCTest.
- Pure-core suites need no privileges and run on any Mac.
- Tool-appropriate oracles for the effectful layer: checked-in symbol-graph fixtures (`sdk-api`), an embedded corpus (`sdk-search`), a known framework (`headerdump`), the `SampleAppKit` known-geometry app under `DYLD_INSERT_LIBRARIES` (`uitool`). Every injection integration test asserts the **target is still alive** after the op, with a watchdog for main-thread deadlock.

## Verifying

1. `mise run test` — pure-core unit + golden-file tests. Any Mac.
2. **Oracle** — the tool-appropriate gate above. If a tool can't nail a fact you placed yourself, it's wrong.
3. `uitool doctor` (runtime cluster) — confirm SIP/AMFI/LV/arch each independently before any first-party attempt.
4. **First-party (manual, dev box only)** — the runtime cluster's last gate; never on shared CI.

See `verification-before-completion` — run the verifying command in-turn before claiming success.

## Driving Xcode from the agent (MCP)

Xcode can expose build/test/code-model over MCP via [external agent access](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode). It's **per-machine** — put it in your user or `.mcp.local.json`, never a committed `.mcp.json`. Fall back to `mise run build` / `mise run test` when the bridge isn't available.

## Commit

Focused, atomic commits at natural boundaries — per spec ID, per command + its tests, per cohesive refactor. See `.Codex/rules/commit-discipline.md`.

- **Never commit signed runtime-cluster artifacts.** The `.dylib` / `.framework` / signed CLI are build outputs and an attack tool elsewhere; `.gitignore` excludes them. Containment is load-bearing — never add the dylib or an injection step to a shippable target or a release CI job.

## When to invoke a more specific skill

- Writing tests? → `test-driven-development`
- Claiming work is done? → `verification-before-completion`
- Something unexpected? → `systematic-debugging`
- Implementing a spec end-to-end? → `implementing-a-spec`
