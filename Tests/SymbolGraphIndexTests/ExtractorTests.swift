import Foundation
import TestSupport
import Testing

@testable import SymbolGraphIndex

@Suite(.spec("story.sdk-api.symbol-queries"))
struct ExtractorTests {
  @Test func `builds the target triple from an SDK version`() {
    #expect(Extractor.targetTriple(sdkVersion: "27.0") == "arm64-apple-macos27.0")
    #expect(Extractor.targetTriple(sdkVersion: "26.1") == "arm64-apple-macos26.1")
  }

  @Test func `keys the cache directory by SDK version and module`() {
    let dir = Extractor.cacheDir(sdkVersion: "27.0", module: "AppKit")
    #expect(dir.pathComponents.contains("sdk-api"))
    #expect(dir.pathComponents.contains("27.0"))
    #expect(dir.lastPathComponent == "AppKit")
  }

  @Test func `extract arguments use the explicit macOS SDK`() {
    let args = Extractor.extractArguments(
      module: "AppKit", sdkPath: "/SDK", target: "arm64-apple-macos27.0", outputDir: "/out")
    #expect(args.contains("symbolgraph-extract"))
    #expect(args.contains("-module-name"))
    #expect(args.contains("AppKit"))
    #expect(args.contains("-sdk"))
    #expect(args.contains("/SDK"))
    #expect(args.contains("-target"))
    #expect(args.contains("arm64-apple-macos27.0"))
    #expect(args.contains("-minimum-access-level"))
    #expect(args.contains("public"))
    #expect(args.contains("-output-dir"))
    #expect(args.contains("/out"))
  }
}
