import AppKit
import ObjectiveC

// SPEC: domain.runtime.walker
/// A clean `{x, y, width, height}` rectangle — the JSON shape the snapshots
/// expose instead of a `CGRect`, which encodes as nested `origin`/`size`. Holds
/// raw `Double`s (a `CGFloat` widened, no rounding); deterministic JSON rounding
/// is the `AgentCLI` encoder's concern downstream, not this struct's.
public struct Rect: Sendable, Codable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// Widen a `CGRect` into the flat shape, raw.
  public init(_ rect: CGRect) {
    self.init(
      x: Double(rect.origin.x),
      y: Double(rect.origin.y),
      width: Double(rect.size.width),
      height: Double(rect.size.height))
  }
}

// SPEC: domain.runtime.walker
/// An immutable, `Sendable`, `Codable` snapshot of one `NSView` and its subview
/// tree — the Swift port of FLEX's `FLEXAppKitViewSnapshot`. Captures only the
/// facts read on the main thread; holds **no** live `NSView` (only plain data and
/// nested snapshots), so it is safe to serialize off the main thread and a stored
/// `NSView` field would not compile.
///
/// The frame is carried twice on purpose: `frame` is the raw AppKit frame in the
/// superview's **bottom-left** origin coordinate space, and `frameTopLeft` is the
/// view normalized to a **top-left** origin relative to the window — because
/// AppKit's origin is bottom-left and a view's `isFlipped` varies, a consumer must
/// never infer a top-left rect from `frame` alone. `isFlipped` is emitted beside
/// them so the flip is explicit, not inferred.
public struct ViewSnapshot: Sendable, Codable {
  /// The view's **real** runtime class name — `NSStringFromClass(object_getClass(view)!)`,
  /// the private/KVO subclass the runtime actually instantiated, never the static
  /// Swift type and never an AX role.
  public let runtimeClass: String

  /// The runtime class hierarchy from the immediate superclass up to (and
  /// including) `NSObject`, exclusive of the view's own class (which is
  /// `runtimeClass`).
  public let superclasses: [String]

  /// The raw `NSView.frame`, in its superview's bottom-left-origin coordinates.
  public let frame: Rect

  /// The view normalized to a top-left-origin rect relative to the window's full
  /// frame (titlebar included). Equal to `frame` when no window was supplied.
  public let frameTopLeft: Rect

  /// The view's own `isFlipped` — emitted alongside the frames so a consumer never
  /// infers a top-left origin from `frame` alone.
  public let isFlipped: Bool

  /// `NSView.isHidden`.
  public let hidden: Bool

  /// `NSView.alphaValue`, raw.
  public let alpha: Double

  /// `NSView.identifier`, when one was set.
  public let identifier: String?

  /// The displayed string where the view is text-bearing (`NSControl.stringValue`
  /// / `NSText.string`); `nil` otherwise. What a `text` selector predicate matches.
  public let text: String?

  /// The view's accessibility role (`NSAccessibility`), to cross-reference an AX
  /// dump; `nil` when none.
  public let axRole: String?

  /// Decomposed font where the view (or its cell) carries one; `nil` otherwise.
  public let font: FontSnapshot?

  /// `NSVisualEffectView.material` as a string name, where applicable.
  public let material: String?

  /// `NSVisualEffectView.blendingMode` as a string name, where applicable.
  public let blendingMode: String?

  /// Layer facts where the view is layer-backed (a non-nil `layer`); `nil`
  /// otherwise. A nil layer is normal — an `NSView` is not always layer-backed.
  public let layer: LayerSnapshot?

  /// The view's Auto Layout snapshot — the constraints touching it and its
  /// intrinsic-sizing facts. `nil` when the view participates in no constraints
  /// and reports no intrinsic content size.
  public let constraints: ConstraintNode?

  /// `true` when any class in the runtime superclass chain is an `NSHostingView`
  /// (SwiftUI's AppKit host): below it the class names are SwiftUI internals, but
  /// the layer-backed scaffold is still real and traversed.
  public let swiftUIBoundary: Bool

  /// The number of subviews, always reported even when `children` is truncated.
  public let childCount: Int

  /// `true` when subviews were omitted because the depth bound was reached. A leaf
  /// is never truncated; `childCount` still reports the real subview count.
  public let truncated: Bool

  /// The subview tree, in z-order (back-to-front, AppKit's `subviews` order).
  /// Empty at a leaf or when the depth bound truncated them (`truncated == true`).
  public let children: [ViewSnapshot]

  public init(
    runtimeClass: String,
    superclasses: [String],
    frame: Rect,
    frameTopLeft: Rect,
    isFlipped: Bool,
    hidden: Bool,
    alpha: Double,
    identifier: String?,
    text: String?,
    axRole: String?,
    font: FontSnapshot?,
    material: String?,
    blendingMode: String?,
    layer: LayerSnapshot?,
    constraints: ConstraintNode?,
    swiftUIBoundary: Bool,
    childCount: Int,
    truncated: Bool,
    children: [ViewSnapshot]
  ) {
    self.runtimeClass = runtimeClass
    self.superclasses = superclasses
    self.frame = frame
    self.frameTopLeft = frameTopLeft
    self.isFlipped = isFlipped
    self.hidden = hidden
    self.alpha = alpha
    self.identifier = identifier
    self.text = text
    self.axRole = axRole
    self.font = font
    self.material = material
    self.blendingMode = blendingMode
    self.layer = layer
    self.constraints = constraints
    self.swiftUIBoundary = swiftUIBoundary
    self.childCount = childCount
    self.truncated = truncated
    self.children = children
  }
}

// SPEC: domain.runtime.walker
/// An immutable, `Sendable`, `Codable` snapshot of one top-level `NSWindow` and
/// its `contentView` subtree — the Swift port of FLEX's `FLEXAppKitWindowSnapshot`.
/// Each on-screen window is a tree root; its `contentView` subtree hangs below.
/// Holds no live `NSWindow` / `NSView` — only plain data and nested snapshots.
public struct WindowSnapshot: Sendable, Codable {
  /// The window's **real** runtime `NSWindow` subclass, via `object_getClass`.
  public let runtimeClass: String

  /// `NSWindow.title`, when set.
  public let title: String?

  /// `NSWindow.identifier`, when set.
  public let identifier: String?

  /// `true` when this is the application's key window.
  public let isKey: Bool

  /// `true` when this is the application's main window.
  public let isMain: Bool

  /// `NSWindow.isVisible`.
  public let isVisible: Bool

  /// `true` when the window is an `NSPanel`.
  public let isPanel: Bool

  /// The window frame in screen coordinates (bottom-left origin).
  public let frame: Rect

  /// The snapshot of the window's `contentView` subtree; `nil` when there is no
  /// content view.
  public let contentView: ViewSnapshot?

  /// Attached child windows and sheets, snapshotted recursively. The top-level
  /// walk lists only root windows (no parent, no sheet parent); a modal sheet or
  /// an ordered child window appears here under its parent rather than being
  /// dropped or surfaced as a stray top-level window.
  public let childWindows: [WindowSnapshot]

  public init(
    runtimeClass: String,
    title: String?,
    identifier: String?,
    isKey: Bool,
    isMain: Bool,
    isVisible: Bool,
    isPanel: Bool,
    frame: Rect,
    contentView: ViewSnapshot?,
    childWindows: [WindowSnapshot]
  ) {
    self.runtimeClass = runtimeClass
    self.title = title
    self.identifier = identifier
    self.isKey = isKey
    self.isMain = isMain
    self.isVisible = isVisible
    self.isPanel = isPanel
    self.frame = frame
    self.contentView = contentView
    self.childWindows = childWindows
  }
}
