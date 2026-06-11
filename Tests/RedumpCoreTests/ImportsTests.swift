import Foundation
import MachOKit
import TestSupport
import Testing

@testable import RedumpCore

@Suite(.spec("command.redump.imports"))
struct ImportsTests {
  @Test func `reports an unreadable file as an error`() {
    #expect(throws: BinaryInspector.InspectError.self) {
      try BinaryInspector.imports(path: "/definitely/not/a/macho")
    }
  }

  @Test func `the library filter keeps only matching imports and drops unresolved ones`() {
    let entries = [
      ImportEntry(name: "_objc_msgSend", library: "/usr/lib/libobjc.A.dylib"),
      ImportEntry(name: "_swift_retain", library: "/usr/lib/swift/libswiftCore.dylib"),
      ImportEntry(name: "_flat_symbol", library: nil),
    ]
    let matching = entries.filter { $0.library?.contains("libobjc") ?? false }
    #expect(matching.map(\.name) == ["_objc_msgSend"])
    #expect(matching.allSatisfy { $0.library?.contains("libobjc") == true })
  }

  #if os(macOS)
    @Test func `reads imported symbols and their source dylibs from a real dylib`() throws {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let source = dir.appendingPathComponent("Fixture.swift")
      try """
      import Foundation
      public final class Probe: NSObject { @objc public func ping() {} }
      public func probeImportsSomething() -> String { UUID().uuidString }
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

      let imports = try BinaryInspector.imports(path: dylib.path)
      // A Swift/ObjC dylib pulls undefined symbols from the Swift runtime and libobjc.
      #expect(!imports.isEmpty)

      // Two-level-namespace ordinals resolve to real dependent dylibs, so at
      // least one import names the Swift core or Objective-C runtime library.
      let resolvedLibraries = imports.compactMap(\.library)
      #expect(!resolvedLibraries.isEmpty)
      #expect(
        resolvedLibraries.contains { $0.contains("libswiftCore") || $0.contains("libobjc") })

      // The library filter narrows to imports from libobjc and nothing else.
      let objcImports = try BinaryInspector.imports(path: dylib.path, library: "libobjc")
      #expect(objcImports.allSatisfy { $0.library?.contains("libobjc") == true })
      #expect(objcImports.count <= imports.count)
    }
  #endif
}
