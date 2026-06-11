// swift-tools-version: 6.4
import PackageDescription

// One package, many targets. Library targets are the shared spine
// (AgentCLI first — the machine contract); executable targets are the tools,
// added as each is migrated in. See Specs/ARCHITECTURE.md.
let package = Package(
  name: "apple-platform-tools",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "AgentCLI", targets: ["AgentCLI"])
  ],
  targets: [
    // SPEC: domain.agent-cli — the deterministic JSON / exit-code contract every tool obeys.
    .target(name: "AgentCLI"),
    .testTarget(name: "AgentCLITests", dependencies: ["AgentCLI"]),
  ]
)
