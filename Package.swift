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
    // headerdump: private framework header extraction from Mach-O / the dyld cache.
    // (MachOFoundation will be factored out of HeaderDumpCore's image-loading seam.)
    .target(name: "HeaderDumpRuntimeObjC", publicHeadersPath: "include"),
    .target(
      name: "HeaderDumpCore",
      dependencies: [
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
  ]
)
