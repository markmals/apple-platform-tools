import Foundation
import MachOKit
import TestSupport
import Testing

@testable import RedumpCore

@Suite(.spec("command.redump.info"))
struct BinaryInfoTests {
  @Test func `maps cpu types to architecture names`() {
    #expect(BinaryInspector.archName(.arm64) == "arm64")
    #expect(BinaryInspector.archName(.x86_64) == "x86_64")
    #expect(BinaryInspector.archName(nil) == "unknown")
  }

  @Test func `derives 64-bit-ness from the cpu type`() {
    #expect(BinaryInspector.is64Bit(.arm64) == true)
    #expect(BinaryInspector.is64Bit(.arm) == false)
  }

  @Test func `names common Mach-O file types`() {
    #expect(BinaryInspector.fileTypeName(.dylib) == "dylib")
    #expect(BinaryInspector.fileTypeName(.execute) == "execute")
    #expect(BinaryInspector.fileTypeName(nil) == "unknown")
  }

  @Test func `reports an unreadable file as an error`() {
    #expect(throws: BinaryInspector.InspectError.self) {
      try BinaryInspector.info(path: "/definitely/not/a/macho")
    }
  }

  #if os(macOS)
    @Test func `reads file type, arch, and bitness from a real dylib`() throws {
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

      let info = try BinaryInspector.info(path: dylib.path)
      #expect(info.fileType == "dylib")
      #expect(info.bitness == 64)
      #expect(!info.archs.isEmpty)
      #expect(info.path == dylib.path)
    }
  #endif
}
