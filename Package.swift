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
    // against — a tiny AppKit scene with a pinned layout. A test-support target
    // (NOT a product, never shipped); later the basis of the launchable injection
    // harness. Built only when a test depends on it.
    .target(name: "SampleAppKit"),

    // UIToolServer: the injected in-target server. The dumb forest-shipping
    // bridge — every read op snapshots the live window forest to the requested
    // depth and ships a Capture (domain.uitool.server); the CLI does all
    // navigation/matching over it. The socket transport and the UIToolBoot dylib
    // are the next slices of the injection half.
    .target(name: "UIToolServer", dependencies: ["AgentCLI", "UIToolCore", "RuntimeKit"]),
    .testTarget(
      name: "UIToolServerTests",
      dependencies: ["UIToolServer", "UIToolCore", "RuntimeKit", "SampleAppKit", "TestSupport"]
    ),

    // uitool: the agent-first CLI over UIToolCore. doctor / list-apps are real
    // local system reads; the read verbs (windows/tree/find/node) run over a
    // SnapshotSource — a captured [WindowSnapshot] now, the injected UIToolServer
    // later. attach/detach + the live session source are the deferred injection half.
    .executableTarget(
      name: "uitool",
      dependencies: [
        "AgentCLI",
        "UIToolCore",
        "RuntimeKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Subprocess", package: "swift-subprocess"),
      ]
    ),
    .testTarget(
      name: "UIToolCLITests",
      dependencies: ["uitool", "UIToolCore", "RuntimeKit", "TestSupport"]
    ),
  ]
)
