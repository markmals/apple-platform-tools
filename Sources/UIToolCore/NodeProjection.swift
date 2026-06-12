import AgentCLI
import RuntimeKit

// SPEC: domain.uitool.node
/// The `--include`-only facets a caller can pull on demand. The default node
/// omits all of them (they are the expensive or rarely-read fields); each verb
/// turns on exactly the facets its flags requested, and projection populates only
/// those — everything else stays `nil`.
public struct IncludeFacets: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  /// The full runtime superclass chain (`--include superclasses`).
  public static let superclasses = IncludeFacets(rawValue: 1 << 0)
  /// `NSVisualEffectView.blendingMode` (`--include blendingMode`).
  public static let blendingMode = IncludeFacets(rawValue: 1 << 1)
  /// The full recursive `LayerSnapshot` (`--include layer`).
  public static let layer = IncludeFacets(rawValue: 1 << 2)
  /// The full `ConstraintNode` (`--include constraints`).
  public static let constraints = IncludeFacets(rawValue: 1 << 3)
}

// SPEC: domain.uitool.node
extension Node {
  /// The decimal precision the node commits to: frame and alpha at **1 dp**, so
  /// equal layouts encode byte-identically regardless of float error.
  static let framePlaces = 1

  /// The closed vocabulary of top-level `--fields` paths — every field on
  /// [[domain.uitool.node]], including the `--include`-only facets (which a field
  /// projection may name even when the instance carries them as `nil`). A path whose
  /// head is outside this set is `UNKNOWN_FIELD`; a field that is valid but `nil` on
  /// the instance projects as `null`, never an error. The set mirrors the `Node`
  /// stored properties so it can never silently drift from what encodes.
  static let fieldNames: Set<String> = [
    "node", "parent", "class", "frame", "frameTopLeft", "isFlipped", "hidden", "alpha",
    "identifier", "text", "axRole", "font", "material", "swiftUIBoundary", "childCount",
    "constraintsCount", "superclasses", "blendingMode", "layer", "constraints", "children",
    "truncated",
  ]

  /// Project a view `ViewSnapshot` into a `Node` under `id`, beneath `parent`.
  ///
  /// Default fields are always populated (with `frame`/`frameTopLeft`/`alpha`
  /// rounded to 1 dp via AgentCLI `stableRounded`); the `--include`-only facets in
  /// `include` are pulled from the snapshot, the rest left `nil`. `children` is
  /// populated only when `depth` admits descendants — past it the node carries
  /// `truncated: true` and `children == nil`, mirroring the walker's own depth
  /// bound. `truncated` is `true` when **either** this projection stopped here or
  /// the underlying snapshot was itself truncated.
  public static func projecting(
    _ snapshot: ViewSnapshot,
    id: NodeID,
    parent: NodeID?,
    include: IncludeFacets = [],
    depth: Int = Int.max
  ) -> Node {
    let childIDs = childIDs(of: snapshot, under: id)
    let admitsChildren = depth > 0 && !snapshot.truncated
    let projectedChildren =
      admitsChildren
      ? zip(snapshot.children, childIDs).map { child, childID in
        projecting(child, id: childID, parent: id, include: include, depth: depth - 1)
      }
      : nil
    let stoppedHere = !snapshot.children.isEmpty && (depth <= 0 || snapshot.truncated)

    return Node(
      node: id.stringValue,
      parent: parent?.stringValue,
      class: snapshot.runtimeClass,
      frame: rounded(snapshot.frame),
      frameTopLeft: rounded(snapshot.frameTopLeft),
      isFlipped: snapshot.isFlipped,
      hidden: snapshot.hidden,
      alpha: stableRounded(snapshot.alpha, places: framePlaces),
      identifier: snapshot.identifier,
      text: snapshot.text,
      axRole: snapshot.axRole,
      font: snapshot.font,
      material: snapshot.material,
      swiftUIBoundary: snapshot.swiftUIBoundary,
      childCount: snapshot.childCount,
      constraintsCount: snapshot.constraints?.constraints.count ?? 0,
      superclasses: include.contains(.superclasses) ? snapshot.superclasses : nil,
      blendingMode: include.contains(.blendingMode) ? snapshot.blendingMode : nil,
      layer: include.contains(.layer) ? snapshot.layer : nil,
      constraints: include.contains(.constraints) ? snapshot.constraints : nil,
      children: projectedChildren,
      truncated: stoppedHere)
  }

  /// Project a window root from a `WindowSnapshot`. A window node has no parent
  /// and roots its `contentView` subtree; the window's own non-view fields
  /// (`title`, `isKey`, …) are not [[domain.uitool.node]] fields, so the projected
  /// root is the content view node under the window id, mirroring the spec's
  /// "each entry is a window-rooted node."
  public static func projecting(
    _ window: WindowSnapshot,
    id: NodeID,
    include: IncludeFacets = [],
    depth: Int = Int.max
  ) -> Node {
    guard let contentView = window.contentView else {
      return emptyWindowRoot(window, id: id)
    }
    let contentID = id.appending(mnemonic: StructuralPath.contentView)
    return projecting(contentView, id: contentID, parent: nil, include: include, depth: depth)
  }

  /// A window with no content view still projects a single rooting node so a
  /// `windows` list entry is never absent — the frame is the window frame, raw
  /// fields default to a non-view root.
  private static func emptyWindowRoot(_ window: WindowSnapshot, id: NodeID) -> Node {
    Node(
      node: id.stringValue,
      parent: nil,
      class: window.runtimeClass,
      frame: rounded(window.frame),
      frameTopLeft: rounded(window.frame),
      isFlipped: false,
      hidden: !window.isVisible,
      alpha: 1,
      identifier: window.identifier,
      text: window.title,
      axRole: nil,
      font: nil,
      material: nil,
      swiftUIBoundary: false,
      childCount: 0,
      constraintsCount: 0)
  }

  /// The id of each direct child, in z-order — the parent path plus a per-child
  /// class-mnemonic + same-class-sibling-ordinal segment.
  private static func childIDs(of snapshot: ViewSnapshot, under parent: NodeID) -> [NodeID] {
    var ordinals: [String: Int] = [:]
    return snapshot.children.map { child in
      let mnemonic = StructuralPath.mnemonic(forClass: child.runtimeClass)
      let ordinal = ordinals[mnemonic, default: 0]
      ordinals[mnemonic] = ordinal + 1
      return parent.appending(mnemonic: "\(mnemonic)\(ordinal)")
    }
  }

  /// Round a `Rect` to the node's frame precision (1 dp) on every axis.
  private static func rounded(_ rect: Rect) -> Rect {
    Rect(
      x: stableRounded(rect.x, places: framePlaces),
      y: stableRounded(rect.y, places: framePlaces),
      width: stableRounded(rect.width, places: framePlaces),
      height: stableRounded(rect.height, places: framePlaces))
  }
}

extension NodeID {
  /// Extend a path by one `/<segment>` step, preserving epoch and dropping any
  /// pointer tag (the pure core never carries one).
  func appending(mnemonic segment: String) -> NodeID {
    NodeID(epoch: epoch, structuralPath: "\(structuralPath)/\(segment)")
  }
}
