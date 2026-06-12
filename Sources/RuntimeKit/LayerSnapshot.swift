import AppKit
import ObjectiveC
import QuartzCore

// SPEC: domain.runtime.walker
/// An immutable, `Sendable`, `Codable` snapshot of one `CALayer` and its parallel
/// sublayer tree — the Swift-first port of FLEX's `FLEXAppKitLayer`.
///
/// This is a structure *parallel* to the view tree: `layer.sublayers` is not
/// `view.subviews`, and standalone sublayers that back no view are captured here.
/// `CALayer` is the same class on macOS and iOS, so this shape is cross-platform.
///
/// The snapshot holds only plain data — no `CALayer` / `CGColor` reference — so it
/// is genuinely `Sendable` and serializes to JSON off the main thread. Reading a
/// live layer happens on the main thread (`snapshot(of:)` is `@MainActor`); the
/// resulting value crosses actor and IPC boundaries freely. Every numeric field
/// stores the **raw** value (a `CGFloat`/`Float` widened to `Double`, no rounding)
/// — deterministic JSON rounding is a later concern of the output encoder, not of
/// this struct, which carries the truth as read.
public struct LayerSnapshot: Sendable, Codable {
  /// `false` for a nil layer, `true` for a real one. The one field FLEX implies by
  /// returning a snapshot only where the layer is non-nil; the Swift port always
  /// returns a value, so absence is carried explicitly rather than as `nil`.
  public let present: Bool

  /// The layer's **real** class name — `NSStringFromClass(object_getClass(layer)!)`,
  /// the private/KVO subclass the runtime actually instantiated, never the static
  /// Swift type. Empty for a nil layer.
  public let className: String

  /// `backgroundColor` flattened to baked sRGB hex `#RRGGBBAA`, or `nil` when the
  /// layer has no background color or it could not be resolved to sRGB.
  public let backgroundColor: String?

  /// `cornerRadius` (raw `CGFloat`).
  public let cornerRadius: Double

  /// `maskedCorners.rawValue` — the `CACornerMask` bitmask preserved as its raw
  /// `UInt`, so which corners are masked is recoverable without an AppKit type.
  public let maskedCorners: UInt

  /// `masksToBounds`.
  public let masksToBounds: Bool

  /// `opacity` (raw `Float`, widened to `Double`).
  public let opacity: Double

  /// `borderWidth` (raw `CGFloat`).
  public let borderWidth: Double

  /// `borderColor` flattened to baked sRGB hex `#RRGGBBAA`, or `nil`.
  public let borderColor: String?

  /// `shadowOpacity` (raw `Float`, widened).
  public let shadowOpacity: Double

  /// `shadowRadius` (raw `CGFloat`).
  public let shadowRadius: Double

  /// `shadowOffset.width` (raw `CGFloat`).
  public let shadowOffsetWidth: Double

  /// `shadowOffset.height` (raw `CGFloat`).
  public let shadowOffsetHeight: Double

  /// `shadowColor` flattened to baked sRGB hex `#RRGGBBAA`, or `nil`.
  public let shadowColor: String?

  /// `isHidden`.
  public let isHidden: Bool

  /// `contentsScale` (raw `CGFloat`).
  public let contentsScale: Double

  /// The number of **direct** sublayers, always the true count even when
  /// `sublayers` was truncated at the depth bound. `sublayers?.count ?? 0`.
  public let sublayerCount: Int

  /// `true` when this node still had sublayers at the depth bound and they were
  /// omitted, so the truncation is visible rather than silent.
  public let truncated: Bool

  /// The parallel sublayer tree, recursively. Empty when there are no sublayers or
  /// the depth bound truncated them (`truncated == true`).
  public let sublayers: [LayerSnapshot]
}

extension LayerSnapshot {
  /// CALayer trees are normally shallow, but pathological backing (CATiledLayer
  /// pyramids, WebKit compositing, Metal/AVPlayer stacks) can be deep; cap recursion
  /// so a walk can never overflow the stack on a hostile tree. FLEX's
  /// `kFLEXMaxLayerDepth`.
  public static let defaultMaxDepth = 64

  /// Build a snapshot from a live `CALayer`. A **nil** layer yields a snapshot with
  /// `present == false` (an empty class name, all-default scalars, no sublayers) —
  /// the Swift stand-in for FLEX returning a snapshot only for a non-nil layer.
  ///
  /// Recursion is capped at `maxDepth` (default 64). A node still bearing sublayers
  /// at the floor is marked `truncated`, its `sublayers` left empty, and its
  /// `sublayerCount` still reports the real direct count.
  // SPEC: domain.runtime.walker
  @MainActor
  public static func snapshot(of layer: CALayer?, maxDepth: Int = defaultMaxDepth) -> LayerSnapshot
  {
    guard let layer else { return .absent }
    return snapshot(of: layer, remainingDepth: maxDepth)
  }

  /// A snapshot for a layer that was not present.
  private static var absent: LayerSnapshot {
    LayerSnapshot(
      present: false,
      className: "",
      backgroundColor: nil,
      cornerRadius: 0,
      maskedCorners: 0,
      masksToBounds: false,
      opacity: 0,
      borderWidth: 0,
      borderColor: nil,
      shadowOpacity: 0,
      shadowRadius: 0,
      shadowOffsetWidth: 0,
      shadowOffsetHeight: 0,
      shadowColor: nil,
      isHidden: false,
      contentsScale: 0,
      sublayerCount: 0,
      truncated: false,
      sublayers: [])
  }

  // SPEC: domain.runtime.walker
  @MainActor
  private static func snapshot(of layer: CALayer, remainingDepth: Int) -> LayerSnapshot {
    let sublayers = layer.sublayers ?? []
    let atDepthFloor = !sublayers.isEmpty && remainingDepth <= 0
    let children =
      atDepthFloor
      ? []
      : sublayers.map { snapshot(of: $0, remainingDepth: remainingDepth - 1) }

    return LayerSnapshot(
      present: true,
      className: NSStringFromClass(object_getClass(layer)!),
      backgroundColor: hex(of: layer.backgroundColor),
      cornerRadius: Double(layer.cornerRadius),
      maskedCorners: layer.maskedCorners.rawValue,
      masksToBounds: layer.masksToBounds,
      opacity: Double(layer.opacity),
      borderWidth: Double(layer.borderWidth),
      borderColor: hex(of: layer.borderColor),
      shadowOpacity: Double(layer.shadowOpacity),
      shadowRadius: Double(layer.shadowRadius),
      shadowOffsetWidth: Double(layer.shadowOffset.width),
      shadowOffsetHeight: Double(layer.shadowOffset.height),
      shadowColor: hex(of: layer.shadowColor),
      isHidden: layer.isHidden,
      contentsScale: Double(layer.contentsScale),
      sublayerCount: sublayers.count,
      truncated: atDepthFloor,
      sublayers: children)
  }

  /// A layer color (`CGColor`) flattened to baked sRGB hex `#RRGGBBAA`, or `nil`.
  ///
  /// Every `CALayer` color is a `CGColor` — already a flat, baked color by the time
  /// the walker sees it: the dynamic/catalog identity was lost when the view baked
  /// it into the layer, so only the baked sRGB hex survives (FLEX's
  /// `FLEXAppKitColor` populates just `hex` for a `CGColor` input). A color that
  /// cannot be converted to sRGB — e.g. a pattern color — yields `nil` rather than a
  /// misleading value, faithful to FLEX returning nil on an unconvertible color.
  // SPEC: domain.runtime.walker
  private static func hex(of cgColor: CGColor?) -> String? {
    guard let cgColor else { return nil }
    let flat = NSColor(cgColor: cgColor)
    guard let srgb = flat?.usingColorSpace(.sRGB) else { return nil }
    let r = Int((srgb.redComponent * 255).rounded())
    let g = Int((srgb.greenComponent * 255).rounded())
    let b = Int((srgb.blueComponent * 255).rounded())
    let a = Int((srgb.alphaComponent * 255).rounded())
    return String(format: "#%02X%02X%02X%02X", r, g, b, a)
  }
}
