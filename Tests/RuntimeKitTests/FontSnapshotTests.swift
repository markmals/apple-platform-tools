import AppKit
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.walker
//
// The font oracle: known NSFonts constructed in-process, decomposed by
// `FontSnapshot.snapshot(of:)`, asserted against what was constructed. AppKit
// reads are main-thread, so the suite is `@MainActor`; it needs a logged-in
// (window-server) session to run, which is expected for the walker layer. The
// weight-bucket case pins the load-bearing decomposition: the raw CoreText
// weight trait off the descriptor must map to the named bucket whose
// `NSFont.Weight` constant it was built from.

@MainActor
@Suite(.spec("domain.runtime.walker"))
struct FontSnapshotTests {

  @Test(.scenario("scenario.runtime.walker.font-system-bold"))
  func `a bold system font decomposes to its size family weight and bold trait`() {
    let font = NSFont.systemFont(ofSize: 13, weight: .bold)
    let snapshot = FontSnapshot.snapshot(of: font)

    #expect(snapshot.size == 13)
    #expect(!snapshot.family.isEmpty)
    #expect(snapshot.weightName == "bold")
    #expect(snapshot.traits.contains("bold"))
    // The PostScript name is the font's own fontName, never nil for a real font.
    #expect(snapshot.postScriptName == font.fontName)
  }

  @Test(.scenario("scenario.runtime.walker.font-weight-bucket"))
  func `each system-font weight maps to its named bucket`() {
    // A system font built at a given NSFont.Weight carries that weight's raw
    // value as its descriptor weight trait, so each bucket round-trips exactly.
    let cases: [(weight: NSFont.Weight, name: String)] = [
      (.ultraLight, "ultraLight"),
      (.thin, "thin"),
      (.light, "light"),
      (.regular, "regular"),
      (.medium, "medium"),
      (.semibold, "semibold"),
      (.bold, "bold"),
      (.heavy, "heavy"),
      (.black, "black"),
    ]

    for testCase in cases {
      let font = NSFont.systemFont(ofSize: 12, weight: testCase.weight)
      let snapshot = FontSnapshot.snapshot(of: font)
      #expect(
        snapshot.weightName == testCase.name,
        "weight \(testCase.weight.rawValue) should bucket as \(testCase.name)")
    }
  }

  @Test(.scenario("scenario.runtime.walker.font-raw-weight-trait"))
  func `the weight trait is the raw CoreText value not the NSFontManager 1 to 14 scale`() {
    let semibold = FontSnapshot.snapshot(of: NSFont.systemFont(ofSize: 12, weight: .semibold))
    let regular = FontSnapshot.snapshot(of: NSFont.systemFont(ofSize: 12, weight: .regular))

    // The raw CoreText axis lives in [-1, 1]; the NSFontManager weight is 1–14.
    // A semibold trait must equal the platform's own constant, full precision.
    #expect(semibold.weightTrait == Double(NSFont.Weight.semibold.rawValue))
    #expect(semibold.weightTrait <= 1.0)
    #expect(semibold.weightTrait > regular.weightTrait)
    // Regular sits at (or very near) the zero of the axis.
    #expect(regular.weightTrait == Double(NSFont.Weight.regular.rawValue))
  }

  @Test(.scenario("scenario.runtime.walker.font-traits"))
  func `a monospaced system font surfaces the monoSpace trait`() throws {
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let snapshot = FontSnapshot.snapshot(of: mono)

    #expect(snapshot.traits.contains("monoSpace"))
    #expect(!snapshot.traits.contains("bold"))
  }

  @Test
  func `a plain font with no bold or italic carries an empty trait list for those`() {
    let snapshot = FontSnapshot.snapshot(of: NSFont.systemFont(ofSize: 14, weight: .regular))

    #expect(!snapshot.traits.contains("bold"))
    #expect(!snapshot.traits.contains("italic"))
    #expect(snapshot.family.isEmpty == false)
    #expect(snapshot.size == 14)
  }

  @Test
  func `the snapshot is Codable and round-trips through JSON`() throws {
    let snapshot = FontSnapshot.snapshot(of: NSFont.systemFont(ofSize: 17, weight: .heavy))
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(FontSnapshot.self, from: data)

    #expect(decoded.family == snapshot.family)
    #expect(decoded.size == snapshot.size)
    #expect(decoded.weightTrait == snapshot.weightTrait)
    #expect(decoded.weightName == snapshot.weightName)
    #expect(decoded.postScriptName == snapshot.postScriptName)
    #expect(decoded.traits == snapshot.traits)
  }
}
