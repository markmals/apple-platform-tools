import AppKit

// SPEC: domain.runtime.walker
/// Decomposed `NSFont` facts read off a live font — the Swift port of FLEX's
/// `FLEXAppKitFont`. Emits the **raw CoreText weight trait** *and* the **nearest
/// named weight**, never a lossy `NSFontManager` (1–14) conversion.
///
/// The struct holds only plain data — no `NSFont` reference — so it is genuinely
/// `Sendable` and serializes off the main thread. The live font does not escape
/// `snapshot(of:)`; every field is materialized there.
///
/// Values are stored **raw**: `weightTrait` and `size` carry full `Double`
/// precision. Deterministic JSON rounding is the `AgentCLI` encoder's job, not
/// this struct's.
public struct FontSnapshot: Sendable, Codable {
  /// The font's family name, from `NSFont.familyName`, falling back to
  /// `fontName` when AppKit reports no family. Never empty for a real font.
  public let family: String
  /// The point size, from `NSFont.pointSize`, raw — not rounded.
  public let size: Double
  /// The raw CoreText `NSFontWeightTrait` from the descriptor's
  /// `NSFontTraitsAttribute` dictionary, in `[-1.0, 1.0]`, full precision. `0.0`
  /// when the descriptor omits it. Not the symbolic `bold` flag and not the
  /// 1–14 `NSFontManager` weight — the continuous CoreText axis.
  public let weightTrait: Double
  /// The nearest named bucket (`ultraLight` … `black`) to `weightTrait`.
  public let weightName: String
  /// The PostScript name, from `NSFont.fontName` (e.g. `.SFNS-Bold`); `nil` only
  /// when AppKit reports none.
  public let postScriptName: String?
  /// The symbolic traits present on the font, in a fixed order: `bold`,
  /// `italic`, `expanded`, `condensed`, `monoSpace`, `vertical`, `uiOptimized`.
  public let traits: [String]

  public init(
    family: String,
    size: Double,
    weightTrait: Double,
    weightName: String,
    postScriptName: String?,
    traits: [String]
  ) {
    self.family = family
    self.size = size
    self.weightTrait = weightTrait
    self.weightName = weightName
    self.postScriptName = postScriptName
    self.traits = traits
  }

  /// Decompose `font` into a snapshot.
  ///
  /// The weight is read out of the descriptor's `NSFontTraitsAttribute`
  /// dictionary under the `.weight` key — the raw CoreText axis — not from the
  /// symbolic-traits bitmask and not via `NSFontManager`. `0.0` when the
  /// descriptor omits the key.
  @MainActor
  public static func snapshot(of font: NSFont) -> FontSnapshot {
    let weightTrait = rawWeightTrait(of: font)
    return FontSnapshot(
      family: font.familyName ?? font.fontName,
      size: Double(font.pointSize),
      weightTrait: weightTrait,
      weightName: nearestWeightName(to: weightTrait),
      postScriptName: font.fontName,
      traits: symbolicTraitNames(font.fontDescriptor.symbolicTraits))
  }

  /// The raw `NSFontWeightTrait` out of the descriptor's traits dictionary, or
  /// `0.0` when absent — FLEX's `traitsDict[NSFontWeightTrait].doubleValue ?: 0`.
  private static func rawWeightTrait(of font: NSFont) -> Double {
    let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
    guard let weight = traits?[.weight] as? NSNumber else { return 0.0 }
    return weight.doubleValue
  }

  /// The nearest named weight to a raw CoreText trait, chosen by minimizing
  /// `abs(weight − constant)` over AppKit's own `NSFont.Weight` constants so the
  /// thresholds track the platform rather than hardcoded folklore numbers. Ties
  /// and the empty case resolve to `regular` (the seed default), matching FLEX.
  private static func nearestWeightName(to weight: Double) -> String {
    let buckets: [(value: Double, name: String)] = [
      (NSFont.Weight.ultraLight.rawValue, "ultraLight"),
      (NSFont.Weight.thin.rawValue, "thin"),
      (NSFont.Weight.light.rawValue, "light"),
      (NSFont.Weight.regular.rawValue, "regular"),
      (NSFont.Weight.medium.rawValue, "medium"),
      (NSFont.Weight.semibold.rawValue, "semibold"),
      (NSFont.Weight.bold.rawValue, "bold"),
      (NSFont.Weight.heavy.rawValue, "heavy"),
      (NSFont.Weight.black.rawValue, "black"),
    ]

    var nearest = "regular"
    var bestDelta = Double.greatestFiniteMagnitude
    for bucket in buckets {
      let delta = abs(weight - bucket.value)
      if delta < bestDelta {
        bestDelta = delta
        nearest = bucket.name
      }
    }
    return nearest
  }

  /// The names of the symbolic traits present, in a fixed order — FLEX's
  /// `FLEXSymbolicTraitNames`.
  private static func symbolicTraitNames(_ traits: NSFontDescriptor.SymbolicTraits) -> [String] {
    var names: [String] = []
    if traits.contains(.bold) { names.append("bold") }
    if traits.contains(.italic) { names.append("italic") }
    if traits.contains(.expanded) { names.append("expanded") }
    if traits.contains(.condensed) { names.append("condensed") }
    if traits.contains(.monoSpace) { names.append("monoSpace") }
    if traits.contains(.vertical) { names.append("vertical") }
    if traits.contains(.UIOptimized) { names.append("uiOptimized") }
    return names
  }
}
