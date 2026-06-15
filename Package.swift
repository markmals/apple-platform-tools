// swift-tools-version: 6.4
import PackageDescription

// One package, many targets. Library targets are the shared spine (AgentCLI —
// the machine contract — plus the per-cluster foundations); executable targets
// are the tools, added as each is migrated in. See Specs/ARCHITECTURE.md.
let package = Package(
  name: "apple-platform-tools",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "AgentCLI", targets: ["AgentCLI"]),
    .executable(name: "sdk-api", targets: ["sdk-api"]),
    .executable(name: "sdk-search", targets: ["sdk-search"]),
    .executable(name: "headerdump", targets: ["headerdump"]),
    .executable(name: "redump", targets: ["redump"]),
    .library(name: "RuntimeKit", targets: ["RuntimeKit"]),
    .executable(name: "uitool", targets: ["uitool"]),
    // The injected boot dylib — DYLD_INSERTed (launch) or remote-dlopened (attach)
    // into a get-task-allow target. A dynamic library so it can be loaded into a
    // foreign process. The signed artifact is git-ignored, dev-box only.
    .library(name: "UIToolBoot", type: .dynamic, targets: ["UIToolBoot", "UIToolBootCtor"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.5.0"),
    // Static-analysis cluster: the MachOKit family (Mach-O / dyld-cache / ObjC + Swift section parsing).
    .package(url: "https://github.com/lynnswap/MachOKit.git", from: "0.47.0"),
    .package(
      url: "https://github.com/lynnswap/MachOObjCSection.git",
      revision: "3dbf6a856cbdc856d4d7c1fe6bbf81161e0fbe9c"),
    .package(
      url: "https://github.com/lynnswap/MachOSwiftSection.git",
      revision: "2fbb1a78e316a2beaf2911488ecda6455e205f84"),
    .package(url: "https://github.com/p-x9/swift-objc-dump.git", from: "0.8.0"),
  ],
  targets: [
    // ── Shared spine ────────────────────────────────────────────────
    // SPEC: domain.agent-cli — the deterministic JSON / exit-code contract every tool obeys.
    .target(name: "AgentCLI"),
    // Shared test-only helpers (the .spec / .scenario association traits).
    .target(name: "TestSupport", path: "Tests/Support"),
    .testTarget(name: "AgentCLITests", dependencies: ["AgentCLI", "TestSupport"]),

    // ── SDK-knowledge cluster ───────────────────────────────────────
    // sdk-api: SDK symbol existence + availability over Swift symbol graphs.
    .target(
      name: "SymbolGraphIndex",
      dependencies: [.product(name: "Subprocess", package: "swift-subprocess")]
    ),
    .testTarget(name: "SymbolGraphIndexTests", dependencies: ["SymbolGraphIndex", "TestSupport"]),
    .executableTarget(
      name: "sdk-api",
      dependencies: [
        "AgentCLI",
        "SymbolGraphIndex",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // sdk-search: ranked framework/HIG pattern search over an embedded corpus.
    .target(name: "PatternIndex", resources: [.process("Data")]),
    .testTarget(name: "PatternIndexTests", dependencies: ["PatternIndex", "TestSupport"]),
    .executableTarget(
      name: "sdk-search",
      dependencies: [
        "AgentCLI",
        "PatternIndex",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // ── Static-analysis cluster ─────────────────────────────────────
    // BinaryFoundation: Mach-O / dyld-shared-cache / universal-binary image loading,
    // on the MachOKit family. Shared by headerdump and (later) redump.
    .target(
      name: "BinaryFoundation",
      dependencies: [.product(name: "MachOKit", package: "MachOKit")]
    ),
    .testTarget(
      name: "BinaryFoundationTests",
      dependencies: [
        "BinaryFoundation", "TestSupport", .product(name: "MachOKit", package: "MachOKit"),
      ]
    ),
    // headerdump: private framework header extraction from Mach-O / the dyld cache.
    .target(name: "HeaderDumpRuntimeObjC", publicHeadersPath: "include"),
    .target(
      name: "HeaderDumpCore",
      dependencies: [
        "BinaryFoundation",
        .target(name: "HeaderDumpRuntimeObjC", condition: .when(platforms: [.macOS, .iOS])),
        .product(name: "MachOKit", package: "MachOKit"),
        .product(name: "MachOObjCSection", package: "MachOObjCSection"),
        .product(name: "ObjCDump", package: "swift-objc-dump"),
        .product(name: "MachOSwiftSection", package: "MachOSwiftSection"),
        .product(name: "SwiftInterface", package: "MachOSwiftSection"),
      ]
    ),
    .testTarget(
      name: "HeaderDumpCLITests",
      dependencies: [
        "HeaderDumpCore",
        "TestSupport",
        .target(name: "HeaderDumpRuntimeObjC", condition: .when(platforms: [.macOS, .iOS])),
        .product(name: "MachOKit", package: "MachOKit"),
      ]
    ),
    .executableTarget(name: "headerdump", dependencies: ["HeaderDumpCore"]),

    // redump: reverse-engineering binary inspection. Native Mach-O reads on the
    // MachOKit family now; an IDA/Hopper disassembler backend is a later slice.
    .target(
      name: "RedumpCore",
      dependencies: [.product(name: "MachOKit", package: "MachOKit")]
    ),
    .testTarget(
      name: "RedumpCoreTests",
      dependencies: [
        "RedumpCore", "TestSupport", .product(name: "MachOKit", package: "MachOKit"),
      ]
    ),
    .executableTarget(
      name: "redump",
      dependencies: [
        "AgentCLI", "RedumpCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // ── Live-runtime cluster ────────────────────────────────────────
    // RuntimeKit: a Swift reimplementation of FLEX's headless reflection core +
    // AppKit walker. The pure type-encoding parser is the first unit; the ObjC
    // runtime / AppKit wrappers and the RuntimeKitC native floor follow.
    .target(name: "RuntimeKit"),
    .testTarget(name: "RuntimeKitTests", dependencies: ["RuntimeKit", "TestSupport"]),

    // UIToolCore: the pure projection core for the live-runtime inspector —
    // node model, node-id grammar, Swift-Regex selector + predicate language,
    // tree/find/windows/node projection, JSON-Lines + exit-code contract. Pure
    // over RuntimeKit's snapshots; the injected server (UIToolServer) and boot
    // (UIToolBoot) are the deferred effectful half.
    .target(name: "UIToolCore", dependencies: ["AgentCLI", "RuntimeKit"]),
    .testTarget(
      name: "UIToolCoreTests",
      dependencies: ["UIToolCore", "RuntimeKit", "TestSupport"]
    ),

    // SampleAppKit: the known-geometry oracle the live-runtime cluster is verified
    // against — a tiny AppKit scene with a pinned layout. The library is depended
    // on by UIToolServerTests; SampleAppKitApp wraps it in a real NSApplication as
    // the cooperative injection target for `uitool launch` / `attach`.
    .target(name: "SampleAppKit"),
    .executableTarget(name: "SampleAppKitApp", dependencies: ["SampleAppKit"]),

    // UIToolBoot: the injected boot dylib. An ObjC +load shim (UIToolBootCtor)
    // calls the Swift entry on image load, which starts UIToolServer. Built as a
    // dynamic library (the .library product above) so it can be DYLD_INSERTed or
    // remote-dlopened into a foreign process. The signed dylib is git-ignored.
    .target(name: "UIToolBootCtor"),
    .target(
      name: "UIToolBoot",
      dependencies: ["UIToolServer", "UIToolIPC", "UIToolCore", "UIToolBootCtor"]),

    // UIToolIPC: the effectful socket transport shared by both ends — the POSIX
    // unix-domain-socket primitives, the newline framing, and the CLI's IPCClient.
    // Kept out of the pure UIToolCore; used by UIToolServer (the accept loop) and
    // uitool (the client).
    .target(name: "UIToolIPC", dependencies: ["AgentCLI", "UIToolCore"]),

    // UIToolServer: the injected in-target server. The dumb forest-shipping
    // bridge — every read op snapshots the live window forest to the requested
    // depth and ships a Capture (domain.uitool.server); the CLI does all
    // navigation/matching over it. SocketServer is the accept loop; the bounded
    // main-thread hop bridges to the AppKit reads. The UIToolBoot dylib is next.
    // RuntimeKitC: the native safety floor (its first piece). The ObjC @try/@catch
    // shim for value-fetching getter invocation, which Swift can't guard.
    .target(name: "RuntimeKitC"),
    .target(
      name: "UIToolServer",
      dependencies: ["AgentCLI", "UIToolCore", "RuntimeKit", "RuntimeKitC", "UIToolIPC"]),
    .testTarget(
      name: "UIToolServerTests",
      dependencies: [
        "UIToolServer", "UIToolIPC", "UIToolCore", "RuntimeKit", "SampleAppKit", "TestSupport",
      ]
    ),

    // uitool: the agent-first CLI over UIToolCore. doctor / list-apps are real
    // local system reads; the read verbs (windows/tree/find/node) run over a
    // SnapshotSource — a captured [WindowSnapshot] now, the injected UIToolServer
    // later. attach/detach + the live session source are the deferred injection half.
    // UIToolInject: the mach injector for attach-to-running — task_for_pid +
    // remote-thread dlopen of the boot dylib into an already-running target. Pure
    // Swift: the arm64 instruction encoding and bootstrap-region layout are tested
    // pure code; the mach traps are quarantined in RemoteInjector (the package's
    // one irreducible unsafe boundary). The CLI calls RemoteInjector.inject.
    .target(name: "UIToolInject"),
    .testTarget(name: "UIToolInjectTests", dependencies: ["UIToolInject", "TestSupport"]),
    .executableTarget(
      name: "uitool",
      dependencies: [
        "AgentCLI",
        "UIToolCore",
        "UIToolIPC",
        "UIToolInject",
        "RuntimeKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Subprocess", package: "swift-subprocess"),
      ]
    ),
    .testTarget(
      name: "UIToolCLITests",
      dependencies: ["uitool", "UIToolCore", "UIToolIPC", "RuntimeKit", "TestSupport"]
    ),

    // UIToolIPCTests: the socket transport end-to-end over a loopback — the
    // SocketServer accept loop + IPCClient round-trip, the schema handshake, and
    // the full live read against the SampleAppKit oracle through makeBoundedHandler.
    // All on a stock Mac, no injection.
    .testTarget(
      name: "UIToolIPCTests",
      dependencies: [
        "UIToolIPC", "UIToolServer", "UIToolCore", "RuntimeKit", "SampleAppKit", "AgentCLI",
        "TestSupport",
      ]
    ),
  ]
)
