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
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.5.0"),
  ],
  targets: [
    // ── Shared spine ────────────────────────────────────────────────
    // SPEC: domain.agent-cli — the deterministic JSON / exit-code contract every tool obeys.
    .target(name: "AgentCLI"),
    .testTarget(name: "AgentCLITests", dependencies: ["AgentCLI"]),

    // ── SDK-knowledge cluster ───────────────────────────────────────
    // sdk-api: SDK symbol existence + availability over Swift symbol graphs.
    .target(
      name: "SymbolGraphIndex",
      dependencies: [.product(name: "Subprocess", package: "swift-subprocess")]
    ),
    .testTarget(name: "SymbolGraphIndexTests", dependencies: ["SymbolGraphIndex"]),
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
    .testTarget(name: "PatternIndexTests", dependencies: ["PatternIndex"]),
    .executableTarget(
      name: "sdk-search",
      dependencies: [
        "AgentCLI",
        "PatternIndex",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
  ]
)
