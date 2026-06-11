---
name: macos-development
description: Use when writing or modifying flexscope's Swift/ObjC code — the ArgumentParser CLI, the ObjC bootstrap dylib + headless server, and the FLEX-mac AppKit walker. Covers Swift 6 + ArgumentParser, Swift/ObjC interop, AppKit/Core Animation runtime introspection (reading the live view tree, not building UI), main-thread marshaling, deterministic JSON output, Swift Testing, and arm64e codesigning. Complementary to `implementing-a-spec` (process) and `test-driven-development`.
---

# macOS / Swift Development (flexscope)

How to write flexscope's code. For the _workflow_ of implementing a spec, see `implementing-a-spec`. For _what_ to build, read the spec and `specs/ARCHITECTURE.md`.

flexscope is **three artifacts in one SwiftPM package**, and macOS is the only platform:

- **`flexscope`** — the agent-first CLI. Swift + ArgumentParser. Holds no state; injects, opens the per-pid socket, issues one op, prints JSON, exits.
- **`FlexScopeBoot`** — the injected bootstrap dylib. ObjC; a `__attribute__((constructor))` starts the headless server. Hosts the socket listener + main-thread marshaling + node registry.
- **FLEX-mac** — the AppKit walker + font/constraint decomposition on FLEX's **unmodified** ObjC reflection engine. Lives in the `third_party/FLEX` submodule (branch `macos`); new AppKit code lands here first.

## Stack at a glance

| Concern | Choice | First-party docs |
| --- | --- | --- |
| Language (CLI) | Swift 6 | [docs.swift.org/swift-book](https://docs.swift.org/swift-book/) |
| Argument parser | Swift ArgumentParser | [github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) |
| Language (dylib + framework) | Objective-C / C | [Programming with Objective-C](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/) |
| Runtime introspection | `<objc/runtime.h>` + the FLEX reflection engine | [objc runtime](https://developer.apple.com/documentation/objectivec/objective-c_runtime) |
| Views being read | AppKit + Core Animation | [appkit](https://developer.apple.com/documentation/appkit) · [quartzcore](https://developer.apple.com/documentation/quartzcore) |
| SwiftUI surface | `NSHostingView` (read emitted scaffold only) | [nshostingview](https://developer.apple.com/documentation/swiftui/nshostingview) |
| Concurrency | Swift Concurrency (CLI); GCD main-thread marshaling (server) | [Swift concurrency](https://developer.apple.com/documentation/swift/concurrency) |
| Tests | Swift Testing | [swift-testing](https://developer.apple.com/xcode/swift-testing/) |
| Formatter / linter | swift-format | [github.com/swiftlang/swift-format](https://github.com/swiftlang/swift-format) |
| Package manager | SwiftPM | [swift.org/package-manager](https://www.swift.org/package-manager/) |
| Signing / arch | `codesign` (ad-hoc, arm64e), `otool` / `lipo` | [code signing](https://developer.apple.com/documentation/security/code-signing-services) |

Apple publishes no `/llms.txt` — WebFetch the canonical URLs when you need a reference.

## The purity boundary (write to it)

`specs/ARCHITECTURE.md` defines this; honoring it is what makes flexscope testable without injecting into anything.

- **Pure core** (Swift, no I/O, deterministic): the view-snapshot model, node-ID derivation, the selector/predicate grammar + evaluator, field projection, JSON encoding, exit-code mapping, `doctor`'s parsing of precondition inputs. Unit-test these on any Mac.
- **Effectful shell** (push to the edges, inject): the socket, process injection, every AppKit read, `codesign`, reading live system state.

If a behavior needs injection to test, you drew the boundary wrong — extract the decision logic into the pure core and feed it captured data.

## Idioms

### CLI commands are thin and machine-first

```swift
// SPEC: command.font   (kind added during spec authoring)
import ArgumentParser

struct Font: AsyncParsableCommand {
    @Argument var app: String
    @Option(name: .customLong("at")) var node: String

    func run() async throws {
        let resolved = try await RPCClient.shared.font(app: app, node: node)  // shell
        Output.emit(resolved)                                                 // pure encode → stdout
    }
}
```

- **stdout is the machine payload only.** Diagnostics, progress, warnings → stderr. No prompts, spinners, color, or pagers — ever. Respect `NO_COLOR` but default off regardless.
- **Exit codes are the control channel.** Map errors to the documented codes (`2` usage, `3` not-running, `4` not-attached, `5` stale-node, `6` precondition, `7` timeout, `8` schema). Never exit `0` on failure; a 0-match query is distinct from success-with-output.
- Make the command body a few lines: call the shell, hand the result to the pure encoder.

### Output is deterministic `Codable`

Stable key order, z-order children, fixed-precision floats (1 dp for frames), no addresses/timestamps in the default projection. Same target state → byte-identical bytes, so `diff` is trustworthy and the agent can cache. Use JSON-Lines (one node per line) for tree/find streams; a single object for scalar queries.

### ObjC ↔ Swift interop

The FLEX engine, the walker, and the server are ObjC (they touch the runtime and AppKit on the target's main thread). The CLI is Swift and talks to them **only over the socket** — it does not link AppKit reads directly. Bridge ObjC into Swift via the module's umbrella header; keep the seam narrow.

### AppKit introspection — you are *reading*, never building

The four traps that make wrong frames instead of crashes (so they're silent — assert against the oracle):

- **Real class:** `NSStringFromClass(object_getClass(view))` — the actual private subclass, the whole point vs AX. (`-class` can lie under KVO; use `object_getClass`.)
- **Coordinate flip:** AppKit is bottom-left origin and `isFlipped` varies per view. Emit raw `frame` **and** a normalized top-left window-relative rect **and** `isFlipped`.
- **Nil layers:** `NSView.layer` is nil unless `wantsLayer`. Walk the view tree for structure; attach `CALayer` data only where present. Never assume view↔layer 1:1 — emit the layer tree as a parallel structure cross-linked by node id.
- **Color resolution:** resolve `NSColor` via the window's `effectiveAppearance` + `usingColorSpace:` before reading components; catalog/dynamic colors throw otherwise. Report the appearance context.

### Main-thread marshaling is load-bearing

All AppKit reads run on the **target's** main thread; the socket loop is off-main. Off-main AppKit access crashes the *target*, not flexscope. Snapshot quickly on main into an immutable model, serialize to JSON off-main, and bound every hop:

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

Keep per-request main-thread work tiny and bounded by `maxDepth`. Avoid the snapshot-image path entirely — it mutates the hierarchy.

### arm64e + signing

Build **arm64e** (a plain-arm64 dylib fails dyld with "missing compatible architecture" — a silent, confusing failure `doctor` must surface). Ad-hoc sign every artifact (`codesign --force --sign - --options runtime --entitlements …`); the dylib/framework carry `com.apple.security.cs.disable-library-validation`. Verify with `lipo -archs`, `file`, and `codesign -dv`. `scripts/sign.sh` does this idempotently and stamps "never distribute". Never notarize, never distribute.

### Tests at the pure-core layer, oracle for the rest

```swift
import Testing

@Suite("domain.node-id")
struct NodeIDTests {
    @Test("[scenario.node-id.stable] same tree shape yields the same id")
    func stable() {
        let id = NodeID.derive(path: ["w0", "cv", "sv2"], epoch: 7, ptr: 0xA3F9)
        #expect(id == "7:w0/cv/sv2#a3f9")
    }
}
```

- `@Suite` name = the spec ID; `@Test` display name starts with `[scenario.<id>]` — drift tooling greps that prefix.
- Pure-core suites need no SIP changes and no injection.
- Injection-dependent behavior is verified against the **`SampleAppKit` oracle** (known frame / font / constraint), injected via `DYLD_INSERT_LIBRARIES`. Every integration test asserts the **target is still alive** after the op, with a watchdog for main-thread deadlock.

## Verifying

No simulator — flexscope is a host-side tool that reads other macOS processes. The escalating ladder:

1. `mise run test` — pure-core unit + golden-file schema tests. Any Mac, no SIP.
2. **Oracle:** relaunch `SampleAppKit` under `DYLD_INSERT_LIBRARIES`, run the verb, assert the known geometry/font/constraint (including the normalized-frame flip). If flexscope can't nail a frame you placed yourself, it's wrong.
3. `flexscope doctor` — confirm SIP/AMFI/LV/arch each independently before any first-party attempt.
4. **First-party (manual, dev box only):** Notes/Mail smoke — tree returns >0 nodes, fonts resolve, no crash-in-target, `ax-diff` non-empty.

See `verification-before-completion` — run the verifying command in-turn before claiming success.

## Driving Xcode from the agent (MCP)

Xcode can expose build/test/code-model over MCP via [external agent access](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode). It's **per-machine** (Xcode must be running with the feature on) — put it in your user or `.mcp.local.json`, never a committed `.mcp.json`. Fall back to `mise run build` / `mise run test` when the bridge isn't available.

## When to invoke a more specific skill

- Writing tests? → `test-driven-development`
- Claiming work is done? → `verification-before-completion`
- Something unexpected? → `systematic-debugging`
- Implementing a spec end-to-end? → `implementing-a-spec`

## Commit

Focused, atomic commits at natural boundaries — per spec ID, per command + its tests, per cohesive refactor. See `.claude/rules/commit-discipline.md`.

flexscope-specific notes:

- **Submodule bumps go alone.** A `third_party/FLEX` pointer change is its own commit (`chore: bump FLEX submodule to <sha>`) — never bundled with feature code.
- **Never commit signed artifacts.** The `.dylib` / `.framework` / signed CLI are build outputs and an attack tool elsewhere; `.gitignore` excludes them.
- **Containment is load-bearing.** Never add the dylib or an injection step to a shippable target, a release CI job, or a committed entitlements file outside this repo.
