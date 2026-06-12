import AgentCLI
import RuntimeKit

// SPEC: domain.uitool.node
/// The canonical agent-facing record for one element of a target app's runtime
/// view tree — the **projection** of a RuntimeKit `ViewSnapshot` / `WindowSnapshot`
/// into the JSON every `uitool` query verb returns.
///
/// "The walker is the source, the node is the shape." A snapshot carries *raw*
/// values; the node is that snapshot after `UIToolCore` applies deterministic
/// rounding (1 dp on `frame`/`frameTopLeft`/`alpha`, via AgentCLI `stableRounded`),
/// stable key order (the AgentCLI encoder), and node-id stringification. No field
/// exists here that the walker does not supply.
///
/// Field membership tracks the spec's default-vs-`--include` split exactly: the
/// default projection is always present; `superclasses`, `blendingMode`, `layer`,
/// and the full `constraints` list are `--include`-only and default to `nil`,
/// left unset unless a caller requests the facet. `constraintsCount` is always
/// present (a cheap scalar); the full `ConstraintNode` rides only under
/// `--include constraints`.
public struct Node: Sendable, Codable {
  // Identity (default).
  /// Stable id — see [[domain.uitool.node-id]].
  public let node: String
  /// Parent node id; `nil` at a window root.
  public let parent: String?

  // Default projection.
  /// The **real** runtime class — the walker's `runtimeClass`, the private
  /// subclass, never an AX role.
  public let `class`: String
  /// Raw `NSView` coords (bottom-left origin), 1 dp.
  public let frame: Rect
  /// Normalized top-left, window-relative, 1 dp.
  public let frameTopLeft: Rect
  /// The view's `isFlipped`.
  public let isFlipped: Bool
  /// `isHidden`.
  public let hidden: Bool
  /// `alphaValue`, 1 dp.
  public let alpha: Double
  /// `NSUserInterfaceItemIdentifier` if set.
  public let identifier: String?
  /// The view's text content where it carries one; `nil` otherwise.
  public let text: String?
  /// Cross-reference to the AX dump.
  public let axRole: String?
  /// The walker's composed `FontSnapshot`, carried verbatim; `nil` with no font.
  public let font: FontSnapshot?
  /// `NSVisualEffectView.material` where applicable.
  public let material: String?
  /// `true` at an `NSHostingView`; below it class names are SwiftUI internals.
  public let swiftUIBoundary: Bool
  /// Number of subviews.
  public let childCount: Int
  /// Count only in the node; the full list rides `--include constraints`.
  public let constraintsCount: Int

  // `--include`-only facets — `nil` unless the caller requested them.
  /// The full runtime class chain (`--include superclasses`).
  public let superclasses: [String]?
  /// `NSVisualEffectView.blendingMode` (`--include`).
  public let blendingMode: String?
  /// The full recursive `LayerSnapshot` (`--include layer`).
  public let layer: LayerSnapshot?
  /// Every touching constraint + intrinsic-sizing facts (`--include constraints`).
  public let constraints: ConstraintNode?

  // Children, present only within `--depth`.
  /// The subview tree, in z-order; `nil` past the depth bound.
  public let children: [Node]?
  /// `true` when subviews were omitted because the depth bound was reached.
  public let truncated: Bool

  public init(
    node: String,
    parent: String?,
    class: String,
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
    swiftUIBoundary: Bool,
    childCount: Int,
    constraintsCount: Int,
    superclasses: [String]? = nil,
    blendingMode: String? = nil,
    layer: LayerSnapshot? = nil,
    constraints: ConstraintNode? = nil,
    children: [Node]? = nil,
    truncated: Bool = false
  ) {
    self.node = node
    self.parent = parent
    self.class = `class`
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
    self.swiftUIBoundary = swiftUIBoundary
    self.childCount = childCount
    self.constraintsCount = constraintsCount
    self.superclasses = superclasses
    self.blendingMode = blendingMode
    self.layer = layer
    self.constraints = constraints
    self.children = children
    self.truncated = truncated
  }
}
