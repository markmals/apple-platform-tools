import Foundation
import MachOKit
import TestSupport
import Testing

@testable import HeaderDumpCore

#if canImport(HeaderDumpRuntimeObjC)
  import HeaderDumpRuntimeObjC
#endif

#if canImport(Darwin)
  import Darwin
#endif

private struct FakeFileManager: FileExistenceChecking {
  let existing: Set<String>

  func fileExists(atPath: String) -> Bool {
    existing.contains(atPath)
  }
}

private final class RecordingBuilder: SwiftInterfaceBuilding {
  var preparedCount = 0
  var printedCount = 0
  let output: String

  init(output: String) {
    self.output = output
  }

  func prepare() async throws {
    preparedCount += 1
  }

  func printRoot() async throws -> String {
    printedCount += 1
    return output
  }
}

private final class RecordingFactory: SwiftInterfaceBuildingFactory {
  var makeCount = 0
  let builder: SwiftInterfaceBuilding

  init(builder: SwiftInterfaceBuilding) {
    self.builder = builder
  }

  func makeBuilder(machO: MachOFile) throws -> SwiftInterfaceBuilding {
    makeCount += 1
    return builder
  }
}

private struct ProcessFailure: Error, CustomStringConvertible {
  let status: Int32
  let stdout: String
  let stderr: String

  var description: String {
    "Process failed with status \(status)\nstdout:\n\(stdout)\nstderr:\n\(stderr)"
  }
}

private enum TestError: Error {
  case missingMachO
}

private func runProcess(_ executable: URL, _ arguments: [String]) throws -> (String, String) {
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments

  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr

  try process.run()
  process.waitUntilExit()

  let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
  let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
  let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
  let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

  if process.terminationStatus != 0 {
    throw ProcessFailure(status: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
  }

  return (stdoutText, stderrText)
}

private func makeTempDir() throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func currentEnvValue(_ key: String) -> String? {
  guard let value = getenv(key) else { return nil }
  return String(cString: value)
}

private func withEnvironment<T>(_ values: [String: String?], _ body: () throws -> T) rethrows -> T {
  var previous: [String: String?] = [:]
  for key in values.keys {
    previous[key] = currentEnvValue(key)
  }
  for (key, value) in values {
    if let value {
      setenv(key, value, 1)
    } else {
      unsetenv(key)
    }
  }
  defer {
    for (key, value) in previous {
      if let value {
        setenv(key, value, 1)
      } else {
        unsetenv(key)
      }
    }
  }
  return try body()
}

private func withEnvironment<T>(_ values: [String: String?], _ body: () async throws -> T)
  async rethrows -> T
{
  var previous: [String: String?] = [:]
  for key in values.keys {
    previous[key] = currentEnvValue(key)
  }
  for (key, value) in values {
    if let value {
      setenv(key, value, 1)
    } else {
      unsetenv(key)
    }
  }
  defer {
    for (key, value) in previous {
      if let value {
        setenv(key, value, 1)
      } else {
        unsetenv(key)
      }
    }
  }
  return try await body()
}

#if os(macOS)
  private func buildSwiftFixture(in dir: URL, moduleName: String) throws -> URL {
    let sourceURL = dir.appendingPathComponent("Fixture.swift")
    let source = """
      public struct \(moduleName)Type {
          public init() {}
      }
      """
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)

    let outputURL = dir.appendingPathComponent("\(moduleName).dylib")
    let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    do {
      // Avoid dyld chained fixups in the test fixture to prevent flaky crashes during parsing.
      _ = try runProcess(
        xcrunURL,
        [
          "--sdk", "macosx",
          "swiftc",
          "-emit-library",
          "-module-name", moduleName,
          sourceURL.path,
          "-Xlinker", "-no_fixup_chains",
          "-o", outputURL.path,
        ]
      )
    } catch {
      // Fallback for older toolchains where `-no_fixup_chains` isn't supported.
      _ = try runProcess(
        xcrunURL,
        [
          "--sdk", "macosx",
          "swiftc",
          "-emit-library",
          "-module-name", moduleName,
          sourceURL.path,
          "-o", outputURL.path,
        ]
      )
    }
    return outputURL
  }

  private func loadMachO(at url: URL) throws -> MachOFile {
    let file = try loadFromFile(url: url)
    switch file {
    case .machO(let machO):
      return machO
    case .fat(let fat):
      let machOFiles = try fat.machOFiles()
      guard let match = machOFiles.first else {
        throw TestError.missingMachO
      }
      return match
    }
  }
#endif

@Suite(.spec("story.headerdump.dump-framework"), .serialized)
struct HeaderDumpCLITests {
  #if canImport(ObjectiveC) && canImport(HeaderDumpRuntimeObjC)
    @Test func `builds an NSObject snapshot with no failed stage`() {
      var failedStage: NSString?
      let snapshot = PHRuntimeObjCInspector.snapshot(for: NSObject.self, failedStage: &failedStage)
      #expect(snapshot != nil)
      #expect(failedStage == nil)
      #expect(snapshot?.name == "NSObject")
    }
  #endif

  @Test func `parses every flag into the matching option`() {
    let args = [
      "-o", "/tmp/out",
      "-r",
      "-b",
      "-h",
      "-s",
      "-j", "OnlyClass",
      "-c",
      "-D",
      "-R",
      "/tmp/input",
    ]

    let parsed = withEnvironment([
      "PH_RUNTIME_ROOT": nil,
      "SIMCTL_CHILD_PH_RUNTIME_ROOT": nil,
    ]) {
      parseArguments(args)
    }

    #expect(parsed != nil)
    #expect(parsed?.inputPath == "/tmp/input")
    #expect(parsed?.options.outputDir.path == "/tmp/out")
    #expect(parsed?.options.recursive == true)
    #expect(parsed?.options.buildOriginalDirs == true)
    #expect(parsed?.options.addHeadersFolder == true)
    #expect(parsed?.options.skipExisting == true)
    #expect(parsed?.options.onlyOneClass == "OnlyClass")
    #expect(parsed?.options.useSharedCache == true)
    #expect(parsed?.options.verbose == true)
    #expect(parsed?.options.useRuntimeFallback == true)
  }

  @Test func `ignores unknown flags and keeps the input path`() {
    let parsed = withEnvironment([
      "PH_RUNTIME_ROOT": nil,
      "SIMCTL_CHILD_PH_RUNTIME_ROOT": nil,
    ]) {
      parseArguments(["-Z", "/tmp/input"])
    }
    #expect(parsed?.inputPath == "/tmp/input")
  }

  @Test func `returns nil when no input path is given`() {
    let parsed = parseArguments(["-r"])
    #expect(parsed == nil)
  }

  @Test func `--help prints usage and exits successfully`() {
    var exitCode: Int32?
    var didPrint = false
    let parsed = parseArguments(
      ["--help"],
      exitHandler: { code in exitCode = code },
      printUsageHandler: { didPrint = true }
    )

    #expect(parsed == nil)
    #expect(exitCode == EXIT_SUCCESS)
    #expect(didPrint == true)
  }

  @Test func `enables the runtime fallback from either env var`() {
    let enabled = withEnvironment([
      "PH_RUNTIME_ROOT": "/tmp/runtime",
      "SIMCTL_CHILD_PH_RUNTIME_ROOT": nil,
    ]) {
      shouldUseRuntimeFallback()
    }
    #expect(enabled == true)

    let enabledSim = withEnvironment([
      "PH_RUNTIME_ROOT": nil,
      "SIMCTL_CHILD_PH_RUNTIME_ROOT": "/tmp/runtime",
    ]) {
      shouldUseRuntimeFallback()
    }
    #expect(enabledSim == true)

    let disabled = withEnvironment([
      "PH_RUNTIME_ROOT": nil,
      "SIMCTL_CHILD_PH_RUNTIME_ROOT": nil,
    ]) {
      shouldUseRuntimeFallback()
    }
    #expect(disabled == false)
  }

  @Test func `logs skipped classes when the env var is set`() {
    let enabled = withEnvironment(["PH_VERBOSE_SKIP": "1"]) {
      shouldLogSkippedClasses()
    }
    #expect(enabled == true)

    let disabled = withEnvironment(["PH_VERBOSE_SKIP": "0"]) {
      shouldLogSkippedClasses()
    }
    #expect(disabled == false)
  }

  @Test func `enables profiling from either env var`() {
    let enabled = withEnvironment([
      "PH_PROFILE": "1",
      "SIMCTL_CHILD_PH_PROFILE": nil,
    ]) {
      shouldProfile()
    }
    #expect(enabled == true)

    let enabledSim = withEnvironment([
      "PH_PROFILE": nil,
      "SIMCTL_CHILD_PH_PROFILE": "1",
    ]) {
      shouldProfile()
    }
    #expect(enabledSim == true)

    let disabled = withEnvironment([
      "PH_PROFILE": "0",
      "SIMCTL_CHILD_PH_PROFILE": nil,
    ]) {
      shouldProfile()
    }
    #expect(disabled == false)
  }

  @Test func `enables Swift event logging from either env var`() {
    let enabled = withEnvironment([
      "PH_SWIFT_EVENTS": "1",
      "SIMCTL_CHILD_PH_SWIFT_EVENTS": nil,
    ]) {
      shouldLogSwiftEvents()
    }
    #expect(enabled == true)

    let enabledSim = withEnvironment([
      "PH_SWIFT_EVENTS": nil,
      "SIMCTL_CHILD_PH_SWIFT_EVENTS": "1",
    ]) {
      shouldLogSwiftEvents()
    }
    #expect(enabledSim == true)

    let disabled = withEnvironment([
      "PH_SWIFT_EVENTS": "0",
      "SIMCTL_CHILD_PH_SWIFT_EVENTS": nil,
    ]) {
      shouldLogSwiftEvents()
    }
    #expect(disabled == false)
  }

  @Test func `resolves a runtime URL under the runtime root when present`() throws {
    let tempDir = try makeTempDir()
    let runtimeRoot = tempDir.appendingPathComponent("Runtime")
    let inputPath = "/System/Library/Frameworks/Foo.framework/Foo"
    let candidate = runtimeRoot.appendingPathComponent(String(inputPath.dropFirst()))
    try FileManager.default.createDirectory(
      at: candidate.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: candidate.path, contents: Data())

    let resolved = withEnvironment(["PH_RUNTIME_ROOT": runtimeRoot.path]) {
      resolveRuntimeURL(URL(fileURLWithPath: inputPath))
    }
    #expect(resolved.path == candidate.path)

    let unresolved = withEnvironment(["PH_RUNTIME_ROOT": runtimeRoot.path]) {
      resolveRuntimeURL(URL(fileURLWithPath: "/System/Library/Frameworks/Bar.framework/Bar"))
    }
    #expect(unresolved.path == "/System/Library/Frameworks/Bar.framework/Bar")
  }

  @Test func `strips the runtime root prefix back to the canonical path`() throws {
    let tempDir = try makeTempDir()
    let runtimeRoot = tempDir.appendingPathComponent("Runtime")
    let inputPath = "/System/Library/Frameworks/Foo.framework/Foo"
    let candidate = runtimeRoot.appendingPathComponent(String(inputPath.dropFirst()))

    let stripped = withEnvironment(["PH_RUNTIME_ROOT": runtimeRoot.path]) {
      stripRuntimeRoot(from: candidate.path)
    }
    #expect(stripped == inputPath)
  }

  @Test func `collapses repeated slashes in a path`() {
    #expect(normalizePath("/tmp//foo///bar") == "/tmp/foo/bar")
  }

  @Test(.scenario("scenario.headerdump.dump-framework.shared-cache"))
  func `includes system and versioned candidates in cache image paths`() {
    let runtimeRoot = "/Runtime"
    let path = "/Runtime/System/Library/Frameworks/Foo.framework/Foo"
    let paths = withEnvironment(["PH_RUNTIME_ROOT": runtimeRoot]) {
      normalizedCacheImagePaths(for: path)
    }
    #expect(paths.first == path)
    #expect(paths.contains("/System/Library/Frameworks/Foo.framework/Foo"))
    #expect(paths.contains("/Runtime/System/Library/Frameworks/Foo.framework/Versions/Current/Foo"))
    #expect(paths.contains("/Runtime/System/Library/Frameworks/Foo.framework/Versions/A/Foo"))
    #expect(Set(paths).count == paths.count)

    let usrPath = "/Runtime/usr/lib/libobjc.A.dylib"
    let usrPaths = withEnvironment(["PH_RUNTIME_ROOT": runtimeRoot]) {
      normalizedCacheImagePaths(for: usrPath)
    }
    #expect(usrPaths.contains("/usr/lib/libobjc.A.dylib"))
  }

  #if canImport(ObjectiveC)
    @Test func `includes versioned candidates in runtime fallback target paths`() {
      let imagePath = "/System/Library/Frameworks/Foo.framework/Foo"
      let targets = runtimeFallbackTargetImagePaths(for: imagePath)

      #expect(targets.contains("/System/Library/Frameworks/Foo.framework/Foo"))
      #expect(targets.contains("/System/Library/Frameworks/Foo.framework/Versions/Current/Foo"))
      #expect(targets.contains("/System/Library/Frameworks/Foo.framework/Versions/A/Foo"))
    }
  #endif

  @Test func `builds bundle write paths with original dirs and headers folder`() {
    let outputRoot = URL(fileURLWithPath: "/tmp/out")
    var options = DumpOptions(outputDir: outputRoot)
    options.buildOriginalDirs = true
    options.addHeadersFolder = true

    let result = writeDirectory(
      for: "/System/Library/Frameworks/Foo.framework/Foo",
      outputRoot: outputRoot,
      options: options
    )
    #expect(result.path == "/tmp/out/System/Library/Frameworks/Foo.framework/Headers")

    options.addHeadersFolder = false
    let resultNoHeaders = writeDirectory(
      for: "/usr/lib/libobjc.A.dylib",
      outputRoot: outputRoot,
      options: options
    )
    #expect(resultNoHeaders.path == "/tmp/out/usr/lib/libobjc.A.dylib")
  }

  @Test func `returns the output root when original dirs are disabled`() {
    let outputRoot = URL(fileURLWithPath: "/tmp/out")
    var options = DumpOptions(outputDir: outputRoot)
    options.buildOriginalDirs = false
    let result = writeDirectory(
      for: "/System/Library/Frameworks/Foo.framework/Foo",
      outputRoot: outputRoot,
      options: options
    )
    #expect(result.path == outputRoot.path)
  }

  @Test func `recognizes bundle directories by their extension`() {
    let frameworkURL = URL(fileURLWithPath: "/tmp/Foo.framework", isDirectory: true)
    let appURL = URL(fileURLWithPath: "/tmp/Foo.app", isDirectory: true)
    let bundleURL = URL(fileURLWithPath: "/tmp/Foo.bundle", isDirectory: true)
    let xpcURL = URL(fileURLWithPath: "/tmp/Foo.xpc", isDirectory: true)
    let appexURL = URL(fileURLWithPath: "/tmp/Foo.appex", isDirectory: true)
    let fileURL = URL(fileURLWithPath: "/tmp/Foo.framework", isDirectory: false)

    #expect(isBundleDirectory(frameworkURL) == true)
    #expect(isBundleDirectory(appURL) == true)
    #expect(isBundleDirectory(bundleURL) == true)
    #expect(isBundleDirectory(xpcURL) == true)
    #expect(isBundleDirectory(appexURL) == true)
    #expect(isBundleDirectory(fileURL) == false)
  }

  @Test func `treats a symlink to a directory as a bundle`() throws {
    let tempDir = try makeTempDir()
    let fm = FileManager.default

    let realBundle = tempDir.appendingPathComponent("Foo.framework", isDirectory: true)
    try fm.createDirectory(at: realBundle, withIntermediateDirectories: true)

    let linkPath = tempDir.appendingPathComponent("Link.framework").path
    try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: realBundle.path)

    // Intentionally omit `isDirectory: true` so `hasDirectoryPath` stays false.
    let linkURL = URL(fileURLWithPath: linkPath)
    #expect(linkURL.hasDirectoryPath == false)
    #expect(isBundleDirectory(linkURL) == true)
  }

  @Test func `treats xpc and appex symlinks to directories as bundles`() throws {
    let tempDir = try makeTempDir()
    let fm = FileManager.default

    let realDir = tempDir.appendingPathComponent("RealDir", isDirectory: true)
    try fm.createDirectory(at: realDir, withIntermediateDirectories: true)

    let xpcLinkPath = tempDir.appendingPathComponent("Link.xpc").path
    try fm.createSymbolicLink(atPath: xpcLinkPath, withDestinationPath: realDir.path)

    let appexLinkPath = tempDir.appendingPathComponent("Link.appex").path
    try fm.createSymbolicLink(atPath: appexLinkPath, withDestinationPath: realDir.path)

    let xpcLinkURL = URL(fileURLWithPath: xpcLinkPath)
    #expect(xpcLinkURL.hasDirectoryPath == false)
    #expect(isBundleDirectory(xpcLinkURL) == true)

    let appexLinkURL = URL(fileURLWithPath: appexLinkPath)
    #expect(appexLinkURL.hasDirectoryPath == false)
    #expect(isBundleDirectory(appexLinkURL) == true)
  }

  @Test func `rebases a cryptex bundle executable back onto the bundle when possible`() {
    let bundleURL = URL(
      fileURLWithPath: "/System/Library/Frameworks/SafariServices.framework", isDirectory: true)
    let resolvedExec = URL(
      fileURLWithPath:
        "/System/Cryptexes/OS/System/Library/Frameworks/SafariServices.framework/SafariServices")

    let expectedRebased = bundleURL.appendingPathComponent("SafariServices")
    let fake = FakeFileManager(existing: [expectedRebased.path])

    let result = resolveBundleExecutableURL(
      bundleURL,
      fileManager: fake,
      bundleExecutableURL: { _ in resolvedExec }
    )
    #expect(result?.path == expectedRebased.path)
  }

  @Test func `resolves the executable inside xpc and appex bundles`() throws {
    let tempDir = try makeTempDir()
    let fm = FileManager.default

    let xpcURL = tempDir.appendingPathComponent("Foo.xpc", isDirectory: true)
    try fm.createDirectory(at: xpcURL, withIntermediateDirectories: true)
    let xpcExec = xpcURL.appendingPathComponent("Foo", isDirectory: false)
    fm.createFile(atPath: xpcExec.path, contents: Data())

    let xpcResolved = resolveBundleExecutableURL(
      xpcURL,
      fileManager: fm,
      bundleExecutableURL: { _ in nil }
    )
    #expect(xpcResolved?.path == xpcExec.path)

    let appexURL = tempDir.appendingPathComponent("Bar.appex", isDirectory: true)
    try fm.createDirectory(at: appexURL, withIntermediateDirectories: true)
    let appexExec = appexURL.appendingPathComponent("Bar", isDirectory: false)
    fm.createFile(atPath: appexExec.path, contents: Data())

    let appexResolved = resolveBundleExecutableURL(
      appexURL,
      fileManager: fm,
      bundleExecutableURL: { _ in nil }
    )
    #expect(appexResolved?.path == appexExec.path)
  }

  @Test func `rejects empty, control, and replacement-character ObjC type names`() {
    #expect(isSaneObjCTypeName("ASAuthorization") == true)
    #expect(isSaneObjCTypeName("") == false)
    #expect(isSaneObjCTypeName("Bad\u{000C}") == false)
    #expect(isSaneObjCTypeName("\u{FFFD}") == false)
  }

  @Test(.scenario("scenario.headerdump.dump-framework.shared-cache"))
  func `picks the shared cache path via the injected file manager`() {
    let runtimeRoot = "/Runtime"
    let simCache = "/Runtime/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64e"
    let fake = FakeFileManager(existing: [simCache])
    let resolved = withEnvironment(["PH_RUNTIME_ROOT": runtimeRoot]) {
      sharedCachePath(fileManager: fake)
    }
    #expect(resolved == simCache)

    let empty = FakeFileManager(existing: [])
    let fallback = withEnvironment(["PH_RUNTIME_ROOT": nil]) {
      sharedCachePath(fileManager: empty)
    }
    #expect(fallback == "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e")
  }

  @Test func `resolves the bundle executable via the injected file manager`() {
    let bundleURL = URL(fileURLWithPath: "/tmp/Foo.framework", isDirectory: true)
    let candidate = bundleURL.appendingPathComponent("Versions/A/Foo")
    let fake = FakeFileManager(existing: [candidate.path])

    let resolved = resolveBundleExecutableURL(
      bundleURL,
      fileManager: fake,
      bundleExecutableURL: { _ in nil }
    )
    #expect(resolved?.path == candidate.path)

    let explicit = URL(fileURLWithPath: "/tmp/BundleExec")
    let resolvedExplicit = resolveBundleExecutableURL(
      bundleURL,
      fileManager: fake,
      bundleExecutableURL: { _ in explicit }
    )
    #expect(resolvedExplicit?.path == explicit.path)
  }

  @Test func `falls back to the canonical path for cache-only bundles`() {
    let bundleURL = URL(fileURLWithPath: "/tmp/Foo.framework", isDirectory: true)
    let fake = FakeFileManager(existing: [])

    let resolved = resolveBundleExecutableURL(
      bundleURL,
      fileManager: fake,
      bundleExecutableURL: { _ in nil }
    )

    #expect(resolved?.path == "/tmp/Foo.framework/Foo")
  }

  @Test func `leaves non-colliding ObjC header names unchanged`() {
    let options = DumpOptions(outputDir: URL(fileURLWithPath: "/tmp/out"))
    let entries = [
      ObjCHeaderEntry(
        symbolKind: .class,
        baseName: "FooHeader",
        headerString: "@interface FooHeader\n@end\n"
      )
    ]

    let resolved = resolveObjCHeaderEntries(entries, options: options)

    #expect(resolved.count == 1)
    #expect(resolved.first?.fileName == "FooHeader.h")
    #expect(resolved.first?.hadNameCollision == false)
  }

  @Test func `disambiguates ObjC header names that differ only by case`() {
    let options = DumpOptions(outputDir: URL(fileURLWithPath: "/tmp/out"))
    let entries = [
      ObjCHeaderEntry(
        symbolKind: .class,
        baseName: "MTRBaseClusterWakeOnLAN",
        headerString: "@interface MTRBaseClusterWakeOnLAN\n@end\n"
      ),
      ObjCHeaderEntry(
        symbolKind: .class,
        baseName: "MTRBaseClusterWakeOnLan",
        headerString: "@interface MTRBaseClusterWakeOnLan\n@end\n"
      ),
    ]

    let resolved = resolveObjCHeaderEntries(entries, options: options)
    let fileNames = Set(resolved.map(\.fileName))

    #expect(fileNames.count == 2)
    #expect(resolved.allSatisfy { $0.hadNameCollision })
    #expect(
      resolved.contains {
        $0.baseName == "MTRBaseClusterWakeOnLAN"
          && $0.fileName.hasPrefix("MTRBaseClusterWakeOnLAN~")
      })
    #expect(
      resolved.contains {
        $0.baseName == "MTRBaseClusterWakeOnLan"
          && $0.fileName.hasPrefix("MTRBaseClusterWakeOnLan~")
      })
  }

  @Test func `disambiguates ObjC header names that collide across symbol kinds`() {
    let options = DumpOptions(outputDir: URL(fileURLWithPath: "/tmp/out"))
    let entries = [
      ObjCHeaderEntry(
        symbolKind: .class,
        baseName: "SharedHeaderName",
        headerString: "@interface SharedHeaderName\n@end\n"
      ),
      ObjCHeaderEntry(
        symbolKind: .protocol,
        baseName: "SharedHeaderName",
        headerString: "@protocol SharedHeaderName\n@end\n"
      ),
    ]

    let resolved = resolveObjCHeaderEntries(entries, options: options)
    let fileNames = Set(resolved.map(\.fileName))

    #expect(fileNames.count == 2)
    #expect(resolved.allSatisfy { $0.hadNameCollision })
    #expect(
      resolved.contains { $0.symbolKind == .class && $0.fileName.hasPrefix("SharedHeaderName~") })
    #expect(
      resolved.contains { $0.symbolKind == .protocol && $0.fileName.hasPrefix("SharedHeaderName~") }
    )
  }

  @Test func `keeps collision suffixes within the filename length limit`() {
    let options = DumpOptions(outputDir: URL(fileURLWithPath: "/tmp/out"))
    let longBaseName = String(repeating: "VeryLongHeaderName", count: 20)
    let entries = [
      ObjCHeaderEntry(
        symbolKind: .class,
        baseName: longBaseName,
        headerString: "@interface LongHeader\n@end\n"
      ),
      ObjCHeaderEntry(
        symbolKind: .protocol,
        baseName: longBaseName,
        headerString: "@protocol LongHeader\n@end\n"
      ),
    ]

    let resolved = resolveObjCHeaderEntries(entries, options: options)

    #expect(Set(resolved.map(\.fileName)).count == 2)
    #expect(resolved.allSatisfy { $0.fileName.utf8.count <= 255 })
    #expect(resolved.allSatisfy { $0.fileName.hasSuffix(".h") })
  }

  @Test func `produces stable ObjC header names regardless of input order`() {
    let options = DumpOptions(outputDir: URL(fileURLWithPath: "/tmp/out"))
    let entries = [
      ObjCHeaderEntry(
        symbolKind: .protocol,
        baseName: "SharedHeaderName",
        headerString: "@protocol SharedHeaderName\n@end\n"
      ),
      ObjCHeaderEntry(
        symbolKind: .class,
        baseName: "MTRBaseClusterWakeOnLan",
        headerString: "@interface MTRBaseClusterWakeOnLan\n@end\n"
      ),
      ObjCHeaderEntry(
        symbolKind: .class,
        baseName: "MTRBaseClusterWakeOnLAN",
        headerString: "@interface MTRBaseClusterWakeOnLAN\n@end\n"
      ),
    ]

    let first = resolveObjCHeaderEntries(entries, options: options)
    let second = resolveObjCHeaderEntries(Array(entries.reversed()), options: options)

    #expect(first == second)
  }

  #if os(macOS)
    @Test(.scenario("scenario.headerdump.dump-framework.swift"))
    func `skips writing the Swift interface when the file already exists`() async throws {
      let tempDir = try makeTempDir()
      let dylibURL = try buildSwiftFixture(in: tempDir, moduleName: "FixtureSkip")
      let machO = try loadMachO(at: dylibURL)
      let outputDir = tempDir.appendingPathComponent("out")
      try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

      let outputURL = outputDir.appendingPathComponent(
        "\(dylibURL.lastPathComponent).swiftinterface")
      try "sentinel".write(to: outputURL, atomically: true, encoding: .utf8)

      var options = DumpOptions(outputDir: outputDir)
      options.skipExisting = true

      let builder = RecordingBuilder(output: "public struct Foo {}")
      let factory = RecordingFactory(builder: builder)

      try await dumpSwift(
        machO: machO,
        imagePath: dylibURL.path,
        outputDir: outputDir,
        options: options,
        interfaceBuilderFactory: factory,
        fileManager: FileManager.default
      )

      #expect(factory.makeCount == 0)
      let contents = try String(contentsOf: outputURL, encoding: .utf8)
      #expect(contents == "sentinel")
    }

    @Test(.scenario("scenario.headerdump.dump-framework.swift"))
    func `skips writing the Swift interface when the output is empty`() async throws {
      let tempDir = try makeTempDir()
      let dylibURL = try buildSwiftFixture(in: tempDir, moduleName: "FixtureEmpty")
      let machO = try loadMachO(at: dylibURL)
      let outputDir = tempDir.appendingPathComponent("out")

      var options = DumpOptions(outputDir: outputDir)
      options.skipExisting = false

      let builder = RecordingBuilder(output: " \n")
      let factory = RecordingFactory(builder: builder)

      try await dumpSwift(
        machO: machO,
        imagePath: dylibURL.path,
        outputDir: outputDir,
        options: options,
        interfaceBuilderFactory: factory,
        fileManager: FileManager.default
      )

      let outputURL = outputDir.appendingPathComponent(
        "\(dylibURL.lastPathComponent).swiftinterface")
      #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
      #expect(factory.makeCount == 1)
    }

    @Test(.scenario("scenario.headerdump.dump-framework.swift"))
    func `writes the Swift interface to the output directory`() async throws {
      let tempDir = try makeTempDir()
      let dylibURL = try buildSwiftFixture(in: tempDir, moduleName: "FixtureWrite")
      let machO = try loadMachO(at: dylibURL)
      let outputDir = tempDir.appendingPathComponent("out")

      var options = DumpOptions(outputDir: outputDir)
      options.skipExisting = false

      let builder = RecordingBuilder(output: "public struct Foo {}")
      let factory = RecordingFactory(builder: builder)

      try await dumpSwift(
        machO: machO,
        imagePath: dylibURL.path,
        outputDir: outputDir,
        options: options,
        interfaceBuilderFactory: factory,
        fileManager: FileManager.default
      )

      let outputURL = outputDir.appendingPathComponent(
        "\(dylibURL.lastPathComponent).swiftinterface")
      #expect(FileManager.default.fileExists(atPath: outputURL.path) == true)
      let contents = try String(contentsOf: outputURL, encoding: .utf8)
      #expect(contents == "public struct Foo {}")
    }

    @Test(.scenario("scenario.headerdump.dump-framework.swift"))
    func `end-to-end run writes a Swift interface file`() async throws {
      let tempDir = try makeTempDir()
      let dylibURL = try buildSwiftFixture(in: tempDir, moduleName: "FixtureE2E")
      let outputDir = tempDir.appendingPathComponent("out")
      let options = DumpOptions(outputDir: outputDir)
      let parsed = ParsedArguments(options: options, inputPath: dylibURL.path)

      try await run(parsed: parsed)

      let outputURL = outputDir.appendingPathComponent(
        "\(dylibURL.lastPathComponent).swiftinterface")
      #expect(FileManager.default.fileExists(atPath: outputURL.path) == true)
    }
  #endif
}
