import Foundation
import MachOKit
import TestSupport
import Testing

@testable import RedumpCore

@Suite(.spec("command.redump.symbols"))
struct SymbolsTests {
  @Test func `reports an unreadable file as an error`() {
    #expect(throws: BinaryInspector.InspectError.self) {
      try BinaryInspector.symbols(path: "/definitely/not/a/macho")
    }
  }

  @Test func `rejects an unrecognized type filter`() throws {
    #expect(throws: SymbolQueryError.self) {
      _ = try BinaryInspector.parseTypeFilter("instructions")
    }
    #expect(try BinaryInspector.parseTypeFilter(nil).admits("data"))
    #expect(try BinaryInspector.parseTypeFilter("all").admits(nil))
  }

  @Test func `rejects a malformed filter regex`() {
    #expect(throws: SymbolQueryError.self) {
      _ = try BinaryInspector.compileFilter("[")
    }
  }

  @Test func `matches a name against a compiled regex, narrowing the set`() throws {
    let names = ["_main", "_probeHandle", "_makeProbe", "_other"]
    let regex = try #require(try BinaryInspector.compileFilter("[Pp]robe"))
    let kept = names.filter { BinaryInspector.matches(regex, $0) }
    #expect(kept == ["_probeHandle", "_makeProbe"])

    // A nil regex admits every name unchanged.
    let all = names.filter { BinaryInspector.matches(nil, $0) }
    #expect(all == names)
  }

  @Test func `classifies symbols by their type filter`() {
    #expect(BinaryInspector.TypeFilter.function.admits("function"))
    #expect(!BinaryInspector.TypeFilter.function.admits("data"))
    #expect(BinaryInspector.TypeFilter.data.admits("data"))
    #expect(BinaryInspector.TypeFilter.data.admits(nil))
    #expect(!BinaryInspector.TypeFilter.data.admits("function"))
    #expect(BinaryInspector.TypeFilter.all.admits("function"))
    #expect(BinaryInspector.TypeFilter.all.admits(nil))
  }

  #if os(macOS)
    @Test func `surfaces an exported Probe symbol from a real dylib`() throws {
      let dylib = try buildProbeDylib()

      let all = try BinaryInspector.symbols(path: dylib.path)
      #expect(all.contains { $0.name.contains("Probe") })
      #expect(all.allSatisfy { $0.address.hasPrefix("0x") })

      let probes = try BinaryInspector.symbols(path: dylib.path, filter: "Probe")
      #expect(!probes.isEmpty)
      #expect(probes.allSatisfy { $0.name.contains("Probe") })
      #expect(probes.count < all.count)
    }

    private func buildProbeDylib() throws -> URL {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let source = dir.appendingPathComponent("Fixture.swift")
      try "public struct Probe {\n  public init() {}\n  public func ping() {}\n}\n".write(
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
      return dylib
    }
  #endif
}
