import Foundation
import MachOKit
import TestSupport
import Testing

@testable import RedumpCore

@Suite(.spec("command.redump.exports"))
struct ExportsTests {
  @Test func `reports an unreadable file as an error`() {
    #expect(throws: BinaryInspector.InspectError.self) {
      try BinaryInspector.exports(path: "/definitely/not/a/macho")
    }
  }

  #if os(macOS)
    @Test func `reads exported symbols from a real dylib`() throws {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let source = dir.appendingPathComponent("Fixture.swift")
      try """
      public struct Probe { public init() {} }
      public func probeExportedFunction() {}
      """.write(to: source, atomically: true, encoding: .utf8)
      let dylib = dir.appendingPathComponent("libProbe.dylib")

      let build = Process()
      build.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      build.arguments = [
        "--sdk", "macosx", "swiftc", "-emit-library", source.path, "-o", dylib.path,
      ]
      try build.run()
      build.waitUntilExit()
      try #require(build.terminationStatus == 0)

      let exports = try BinaryInspector.exports(path: dylib.path)
      #expect(!exports.isEmpty)
      // The exported free function mangles to a stable Swift symbol; assert it is present.
      let names = exports.map(\.name)
      #expect(names.contains { $0.contains("probeExportedFunction") })
    }
  #endif
}
