import AppKit
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.walker
//
// The color oracle: known NSColors constructed in-process, decomposed by
// `ColorSnapshot.snapshot(of:appearance:)`, asserted against what was
// constructed. AppKit reads are main-thread, so the suite is `@MainActor`; it
// needs a logged-in (window-server) session to run, which is expected for the
// walker layer. The catalog case pins the load-bearing guard order: a catalog
// color must resolve without throwing an uncatchable ObjC exception off an
// unguarded component accessor.

@MainActor
@Suite(.spec("domain.runtime.walker"))
struct ColorSnapshotTests {

  @Test(.scenario("scenario.runtime.walker.color-srgb"))
  func `an sRGB color round-trips to its exact RRGGBBAA hex`() {
    let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    let snapshot = ColorSnapshot.snapshot(of: red, appearance: nil)

    #expect(snapshot.hex == "#FF0000FF")
    // A plain sRGB color is not a catalog color and carries no name.
    #expect(snapshot.catalogName == nil)
    // No appearance was supplied.
    #expect(snapshot.appearanceName == nil)
  }

  @Test(.scenario("scenario.runtime.walker.color-srgb"))
  func `a partially transparent sRGB color encodes its alpha channel`() {
    let half = NSColor(srgbRed: 0, green: 0x80 / 255.0, blue: 1, alpha: 0x80 / 255.0)
    let snapshot = ColorSnapshot.snapshot(of: half, appearance: nil)

    #expect(snapshot.hex == "#0080FF80")
  }

  @Test(.scenario("scenario.runtime.walker.color-catalog"))
  func `a catalog color resolves without crashing and reports its name`() {
    // `.labelColor` is a catalog color. The load-bearing guard order means
    // `colorNameComponent` is read (the type is `.catalog`), but the RGBA
    // accessors are read only after conversion to sRGB — so this must not throw
    // an uncatchable ObjC exception.
    let snapshot = ColorSnapshot.snapshot(of: .labelColor, appearance: nil)

    #expect(snapshot.catalogName == "labelColor")
    // Resolved to a concrete sRGB hex (opaque-ish), never the empty string.
    #expect(snapshot.hex.hasPrefix("#"))
    #expect(snapshot.hex.count == 9)
  }

  @Test(.scenario("scenario.runtime.walker.color-appearance"))
  func `the supplied appearance name is recorded and drives resolution`() throws {
    let aqua = try #require(NSAppearance(named: .aqua))
    let snapshot = ColorSnapshot.snapshot(of: .labelColor, appearance: aqua)

    #expect(snapshot.appearanceName == NSAppearance.Name.aqua.rawValue)
    #expect(snapshot.catalogName == "labelColor")
    #expect(snapshot.hex.count == 9)
  }

  @Test(.scenario("scenario.runtime.walker.color-appearance"))
  func `the same catalog color resolves differently under aqua and dark aqua`() throws {
    let aqua = try #require(NSAppearance(named: .aqua))
    let darkAqua = try #require(NSAppearance(named: .darkAqua))

    let light = ColorSnapshot.snapshot(of: .labelColor, appearance: aqua)
    let dark = ColorSnapshot.snapshot(of: .labelColor, appearance: darkAqua)

    // labelColor is near-black in light mode and near-white in dark mode:
    // resolving under the two appearances yields distinct hexes, proving the
    // conversion ran under the requested appearance, not the process default.
    #expect(light.hex != dark.hex)
  }

  @Test
  func `the snapshot is Codable and round-trips through JSON`() throws {
    let snapshot = ColorSnapshot.snapshot(
      of: NSColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 1), appearance: nil)
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(ColorSnapshot.self, from: data)

    #expect(decoded.hex == snapshot.hex)
    #expect(decoded.catalogName == snapshot.catalogName)
    #expect(decoded.appearanceName == snapshot.appearanceName)
  }
}
