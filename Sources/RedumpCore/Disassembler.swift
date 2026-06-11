import Foundation

// SPEC: command.redump.backends
/// A disassembler backend redump can drive for the analysis commands
/// (`functions`, `disasm`, `decompile`, `xrefs`). Backend *detection* is native
/// and testable; actually driving IDA Pro / Hopper requires the paid tools
/// installed and is the remaining, tools-gated slice of redump (it can't be
/// built or verified without them).
public enum Disassembler: String, Encodable, Sendable, CaseIterable {
  case ida
  case hopper
}

// SPEC: command.redump.backends
/// Whether a backend's tool can be found, and where.
public struct BackendStatus: Encodable, Sendable {
  public let backend: String
  public let configured: Bool
  public let path: String?
}

// SPEC: command.redump.backends
/// Locates the disassembler tools, mirroring re-cli's resolution order: an
/// environment override, then known install locations. Pure — it takes the
/// environment and a file-existence check, so it's testable without the tools.
public enum BackendDetector {
  static let envVar: [Disassembler: String] = [.ida: "RE_IDAT64", .hopper: "RE_HOPPER"]

  static let knownPaths: [Disassembler: [String]] = [
    .ida: ["/Applications/IDA Pro/idabin/idat64"],
    .hopper: [
      "/Applications/Hopper Disassembler.app/Contents/MacOS/hopper",
      "/Applications/Hopper Disassembler v5.app/Contents/MacOS/hopper",
      "/Applications/Hopper Disassembler v4.app/Contents/MacOS/hopper",
      "/Applications/Hopper.app/Contents/MacOS/hopper",
    ],
  ]

  /// Resolve where a backend's tool lives, or `nil` if it can't be found.
  /// (re-cli additionally globs `/Applications` for versioned IDA installs and
  /// falls back to `which`; those are effectful and omitted from this pure resolver.)
  public static func resolve(
    _ backend: Disassembler,
    environment: [String: String],
    exists: (String) -> Bool
  ) -> String? {
    if let override = environment[envVar[backend]!], !override.isEmpty { return override }
    for path in knownPaths[backend]! where exists(path) { return path }
    return nil
  }

  /// The status of every backend in the current environment.
  public static func detect(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) -> [BackendStatus] {
    Disassembler.allCases.map { backend in
      let path = resolve(backend, environment: environment, exists: exists)
      return BackendStatus(backend: backend.rawValue, configured: path != nil, path: path)
    }
  }
}
