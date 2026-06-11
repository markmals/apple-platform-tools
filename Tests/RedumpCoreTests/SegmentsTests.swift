import Foundation
import MachOKit
import TestSupport
import Testing

@testable import RedumpCore

@Suite(.spec("command.redump.segments"))
struct SegmentsTests {
  @Test func `hex-encodes addresses with a 0x prefix`() {
    #expect(BinaryInspector.hex(0) == "0x0")
    #expect(BinaryInspector.hex(0x1_0000_0000) == "0x100000000")
  }

  @Test func `reports an unreadable file as an error`() {
    #expect(throws: BinaryInspector.InspectError.self) {
      try BinaryInspector.segments(path: "/definitely/not/a/macho")
    }
  }

  #if os(macOS)
    @Test func `reads a __TEXT segment with a hex start from a real dylib`() throws {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let source = dir.appendingPathComponent("Fixture.swift")
      try "public struct Probe { public init() {} }".write(
        to: source, atomically: true, encoding: .utf8)
      let dylib = dir.appendingPathComponent("libProbe.dylib")

      let build = Process()
      build.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      build.arguments = [
        "--sdk", "macosx", "swiftc", "-emit-library", source.path, "-o", dylib.path,
      ]
      try build.run()
      build.waitUntilExit()
      try #require(build.terminationStatus == 0)

      let segments = try BinaryInspector.segments(path: dylib.path)
      let text = try #require(segments.first { $0.name == "__TEXT" })
      #expect(text.start.hasPrefix("0x"))
      #expect(text.start.count > 2)
      #expect(text.end.hasPrefix("0x"))
    }
  #endif
}
