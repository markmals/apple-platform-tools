import Foundation
import MachOKit
import TestSupport
import Testing

@testable import RedumpCore

@Suite(.spec("command.redump.strings"))
struct StringsTests {
  @Test func `reports an unreadable file as an error`() {
    #expect(throws: BinaryInspector.InspectError.self) {
      try BinaryInspector.strings(path: "/definitely/not/a/macho")
    }
  }

  #if os(macOS)
    /// A C string literal compiled into a dylib lands in `__TEXT,__cstring`
    /// (verified: `swiftc` may instead place Swift literals in `__TEXT,__const`,
    /// so the fixture is C, where the placement is deterministic).
    @Test func `reads a known C string literal from __TEXT,__cstring`() throws {
      let dylib = try buildCDylib(
        body: """
          const char *redump_marker(void) { return "REDUMP_MARKER_STRING"; }
          """)

      let entries = try BinaryInspector.strings(path: dylib.path)
      let marker = entries.first { $0.value == "REDUMP_MARKER_STRING" }
      try #require(marker != nil)
      #expect(marker!.address.hasPrefix("0x"))
    }

    @Test func `min-length drops strings shorter than the threshold`() throws {
      let dylib = try buildCDylib(
        body: """
          const char *redump_short(void) { return "ab"; }
          const char *redump_long(void) { return "abcdefgh"; }
          """)

      let longOnly = try BinaryInspector.strings(path: dylib.path, minLength: 5)
      #expect(longOnly.contains { $0.value == "abcdefgh" })
      #expect(!longOnly.contains { $0.value == "ab" })

      let bothKept = try BinaryInspector.strings(path: dylib.path, minLength: 2)
      #expect(bothKept.contains { $0.value == "ab" })
    }

    @Test func `filter keeps only values matching the regex`() throws {
      let dylib = try buildCDylib(
        body: """
          const char *redump_keep(void) { return "KEEP_THIS_STRING"; }
          const char *redump_drop(void) { return "DROP_THAT_STRING"; }
          """)

      let kept = try BinaryInspector.strings(path: dylib.path, filter: "^KEEP_")
      #expect(kept.contains { $0.value == "KEEP_THIS_STRING" })
      #expect(!kept.contains { $0.value == "DROP_THAT_STRING" })
    }

    /// Compiles `body` (C source) into a dylib with `clang -dynamiclib` and
    /// returns its URL. C string literals land in `__TEXT,__cstring` reliably,
    /// which is what `redump strings` reads.
    private func buildCDylib(body: String) throws -> URL {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let source = dir.appendingPathComponent("fixture.c")
      try body.write(to: source, atomically: true, encoding: .utf8)
      let dylib = dir.appendingPathComponent("libfixture.dylib")

      let build = Process()
      build.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      build.arguments = [
        "--sdk", "macosx", "clang", "-dynamiclib", source.path, "-o", dylib.path,
      ]
      try build.run()
      build.waitUntilExit()
      try #require(build.terminationStatus == 0)
      return dylib
    }
  #endif
}
