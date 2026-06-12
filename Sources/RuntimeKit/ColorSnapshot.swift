import AppKit
import ObjectiveC

// SPEC: domain.runtime.walker
/// A resolved-color fact read off a live `NSColor` — the Swift port of FLEX's
/// `FLEXAppKitColor`. The unambiguous sRGB hex, plus, for a catalog/dynamic
/// color, the catalog name and the appearance the color was resolved under.
///
/// The struct holds only plain data — no `NSColor` reference — so it is
/// genuinely `Sendable` and serializes off the main thread. The live color does
/// not escape `snapshot(of:appearance:)`; every field is materialized there.
///
/// Values are stored **raw**: the hex is the exact `lround(component * 255)` of
/// each sRGB channel, no deterministic rounding applied here. Deterministic JSON
/// is the `AgentCLI` encoder's job, not this struct's.
public struct ColorSnapshot: Sendable, Codable {
  /// sRGB hex `#RRGGBBAA`, uppercase. Empty when the color could not be
  /// converted to an sRGB color space (e.g. a pattern color) — never a
  /// misleading value read off an unguarded accessor.
  public let hex: String
  /// The catalog/dynamic name (e.g. `"labelColor"`) when the color is a catalog
  /// color; `nil` otherwise.
  public let catalogName: String?
  /// The appearance the color was resolved under (e.g.
  /// `"NSAppearanceNameDarkAqua"`); `nil` when no appearance was supplied.
  public let appearanceName: String?

  public init(hex: String, catalogName: String?, appearanceName: String?) {
    self.hex = hex
    self.catalogName = catalogName
    self.appearanceName = appearanceName
  }

  /// Resolve `color` to a snapshot under `appearance`.
  ///
  /// The guard order is **load-bearing**: NSColor's component accessors throw
  /// Objective-C exceptions on the wrong color type, and Swift cannot catch an
  /// ObjC exception, so the type is checked *before* any accessor is read.
  ///
  /// 1. `colorNameComponent` is read only when `color.type == .catalog`.
  /// 2. RGBA components are read only on a color first converted to sRGB.
  /// 3. The conversion runs under `appearance` so a live catalog/dynamic color
  ///    resolves under the requested appearance, not the process default.
  @MainActor
  public static func snapshot(of color: NSColor, appearance: NSAppearance?) -> ColorSnapshot {
    // Catalog/dynamic NAME — only where the color genuinely is a catalog color;
    // `colorNameComponent` throws on any other type.
    let catalogName = color.type == .catalog ? color.colorNameComponent : nil

    let resolved = resolveToSRGB(color, under: appearance)
    return ColorSnapshot(
      hex: hex(ofSRGB: resolved),
      catalogName: catalogName,
      appearanceName: appearance?.name.rawValue)
  }

  /// Convert `color` to the sRGB color space, *under* `appearance` when one is
  /// supplied — required for a live catalog/dynamic color, which otherwise
  /// resolves under the wrong appearance or returns nil. Returns `nil` for a
  /// color that has no sRGB representation (e.g. a pattern color).
  @MainActor
  private static func resolveToSRGB(_ color: NSColor, under appearance: NSAppearance?)
    -> NSColor?
  {
    guard let appearance else {
      return color.usingColorSpace(.sRGB)
    }
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolved = color.usingColorSpace(.sRGB)
    }
    return resolved
  }

  /// sRGB hex `#RRGGBBAA` of a color already converted to sRGB, or `""` when the
  /// color is nil. The caller must convert first — reading components on a
  /// non-RGB color throws.
  private static func hex(ofSRGB srgb: NSColor?) -> String {
    guard let srgb else { return "" }
    let r = Int(lround(srgb.redComponent * 255.0))
    let g = Int(lround(srgb.greenComponent * 255.0))
    let b = Int(lround(srgb.blueComponent * 255.0))
    let a = Int(lround(srgb.alphaComponent * 255.0))
    return String(format: "#%02X%02X%02X%02X", r, g, b, a)
  }
}
