import AppKit
import ObjectiveC

// SPEC: domain.runtime.walker
/// One view's Auto Layout snapshot — the Swift port of FLEX's `FLEXConstraintNode`
/// (with its `FLEXConstraint` / `FLEXConstraintItem` helpers). Captures every
/// `NSLayoutConstraint` touching a single `NSView` in both directions, plus the
/// view's intrinsic-sizing facts. Plain data only: no `NSView` / `NSLayoutConstraint`
/// reference is retained, so the snapshot is genuinely `Sendable` and serializes
/// off the main thread. Values are stored **raw** (`CGFloat` → `Double`, no
/// rounding); deterministic JSON rounding is the encoder's concern downstream.
public struct ConstraintNode: Sendable, Codable {
  /// `view.translatesAutoresizingMaskIntoConstraints`.
  public let translatesAutoresizingMaskIntoConstraints: Bool
  /// `view.intrinsicContentSize`, raw. An axis with no intrinsic metric is
  /// `NSView.noIntrinsicMetric` (`-1`), carried verbatim.
  public let intrinsicContentSize: IntrinsicSize
  /// `contentHuggingPriority(for: .horizontal)` raw value.
  public let contentHuggingHorizontal: Double
  /// `contentHuggingPriority(for: .vertical)` raw value.
  public let contentHuggingVertical: Double
  /// `contentCompressionResistancePriority(for: .horizontal)` raw value.
  public let compressionResistanceHorizontal: Double
  /// `contentCompressionResistancePriority(for: .vertical)` raw value.
  public let compressionResistanceVertical: Double
  /// The constraints touching the view, both directions, deduplicated.
  public let constraints: [ConstraintDescription]

  public init(
    translatesAutoresizingMaskIntoConstraints: Bool,
    intrinsicContentSize: IntrinsicSize,
    contentHuggingHorizontal: Double,
    contentHuggingVertical: Double,
    compressionResistanceHorizontal: Double,
    compressionResistanceVertical: Double,
    constraints: [ConstraintDescription]
  ) {
    self.translatesAutoresizingMaskIntoConstraints = translatesAutoresizingMaskIntoConstraints
    self.intrinsicContentSize = intrinsicContentSize
    self.contentHuggingHorizontal = contentHuggingHorizontal
    self.contentHuggingVertical = contentHuggingVertical
    self.compressionResistanceHorizontal = compressionResistanceHorizontal
    self.compressionResistanceVertical = compressionResistanceVertical
    self.constraints = constraints
  }

  /// Snapshot the Auto Layout facts of a live view. Reads `view.constraints` and
  /// every ancestor's constraints on the main thread, keeping only the ones that
  /// touch `view` (it is the first or second item), deduplicated by identity.
  @MainActor
  public static func snapshot(of view: NSView) -> ConstraintNode {
    let size = view.intrinsicContentSize
    return ConstraintNode(
      translatesAutoresizingMaskIntoConstraints: view.translatesAutoresizingMaskIntoConstraints,
      intrinsicContentSize: IntrinsicSize(width: Double(size.width), height: Double(size.height)),
      contentHuggingHorizontal: Double(view.contentHuggingPriority(for: .horizontal).rawValue),
      contentHuggingVertical: Double(view.contentHuggingPriority(for: .vertical).rawValue),
      compressionResistanceHorizontal: Double(
        view.contentCompressionResistancePriority(for: .horizontal).rawValue),
      compressionResistanceVertical: Double(
        view.contentCompressionResistancePriority(for: .vertical).rawValue),
      constraints: touchingConstraints(of: view))
  }

  /// The constraints that touch `view` (first or second item), in both
  /// directions: the view's own, then every ancestor's, deduplicated by
  /// `ObjectIdentifier`. A view also holds constraints purely between its
  /// descendants; those don't touch it and are excluded by the touch filter.
  @MainActor
  private static func touchingConstraints(of view: NSView) -> [ConstraintDescription] {
    var seen: Set<ObjectIdentifier> = []
    var out: [ConstraintDescription] = []

    func collect(_ constraints: [NSLayoutConstraint]) {
      for constraint in constraints {
        guard constraint.firstItem === view || constraint.secondItem === view else { continue }
        guard seen.insert(ObjectIdentifier(constraint)).inserted else { continue }
        out.append(ConstraintDescription(constraint, target: view))
      }
    }

    collect(view.constraints)
    var ancestor = view.superview
    while let current = ancestor {
      collect(current.constraints)
      ancestor = current.superview
    }
    return out
  }
}

// SPEC: domain.runtime.walker
/// A view's `intrinsicContentSize`, carried raw. An axis with no intrinsic metric
/// is `NSView.noIntrinsicMetric` (`-1`); that sentinel is preserved here — the
/// `-1` → "no intrinsic metric" interpretation is a presentation concern.
public struct IntrinsicSize: Sendable, Codable {
  public let width: Double
  public let height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

// SPEC: domain.runtime.walker
/// One `NSLayoutConstraint`, decomposed — a port of FLEX's `FLEXConstraint`.
/// Reads as `first.attr (relation) second.attr * multiplier + constant @ priority`.
public struct ConstraintDescription: Sendable, Codable {
  /// The constraint's first side (`firstItem` + `firstAttribute`).
  public let first: ConstraintItem
  /// The relation, as a readable string: `equal`, `lessThanOrEqual`, or
  /// `greaterThanOrEqual`.
  public let relation: String
  /// The constraint's second side (`secondItem` + `secondAttribute`); the
  /// absent side of a constant constraint reads as `kind == "none"`.
  public let second: ConstraintItem
  /// `NSLayoutConstraint.multiplier`.
  public let multiplier: Double
  /// `NSLayoutConstraint.constant`, raw.
  public let constant: Double
  /// `NSLayoutConstraint.priority.rawValue`.
  public let priority: Double
  /// `NSLayoutConstraint.isActive`.
  public let isActive: Bool
  /// `NSLayoutConstraint.identifier`, when one was set.
  public let identifier: String?

  public init(
    first: ConstraintItem,
    relation: String,
    second: ConstraintItem,
    multiplier: Double,
    constant: Double,
    priority: Double,
    isActive: Bool,
    identifier: String?
  ) {
    self.first = first
    self.relation = relation
    self.second = second
    self.multiplier = multiplier
    self.constant = constant
    self.priority = priority
    self.isActive = isActive
    self.identifier = identifier
  }

  /// Decompose a constraint. `target` is the view the owning `ConstraintNode`
  /// describes, used to mark which side `is` the target.
  @MainActor
  init(_ constraint: NSLayoutConstraint, target: NSView) {
    self.first = ConstraintItem(
      constraint.firstItem, attribute: constraint.firstAttribute, target: target)
    self.relation = Self.name(of: constraint.relation)
    self.second = ConstraintItem(
      constraint.secondItem, attribute: constraint.secondAttribute, target: target)
    self.multiplier = Double(constraint.multiplier)
    self.constant = Double(constraint.constant)
    self.priority = Double(constraint.priority.rawValue)
    self.isActive = constraint.isActive
    self.identifier = constraint.identifier
  }

  /// The readable name of a layout relation — a port of FLEX's `FLEXRelationName`.
  /// An unrecognized raw value falls through to `relation(n)`.
  private static func name(of relation: NSLayoutConstraint.Relation) -> String {
    switch relation {
    case .lessThanOrEqual: return "lessThanOrEqual"
    case .equal: return "equal"
    case .greaterThanOrEqual: return "greaterThanOrEqual"
    @unknown default: return "relation(\(relation.rawValue))"
    }
  }
}

// SPEC: domain.runtime.walker
/// One side of a constraint — a port of FLEX's `FLEXConstraintItem`. Captures the
/// item's runtime class, its attribute, its kind, and whether it is the target.
public struct ConstraintItem: Sendable, Codable {
  /// The item's runtime class name, from `object_getClass` — the private subclass,
  /// not the static Swift type. `nil` for the absent second item of a constant
  /// constraint.
  public let className: String?
  /// The attribute, as a readable string: `width`, `leading`, `notAnAttribute`, …
  public let attribute: String
  /// `"view"`, `"layoutGuide"`, `"other"`, or `"none"` (an absent item).
  public let kind: String
  /// True when this item **is** the view the owning `ConstraintNode` describes.
  public let isTarget: Bool

  public init(className: String?, attribute: String, kind: String, isTarget: Bool) {
    self.className = className
    self.attribute = attribute
    self.kind = kind
    self.isTarget = isTarget
  }

  /// Build one side from a (possibly nil) constraint item. `NSView` is checked
  /// before `NSLayoutGuide`, faithful to FLEX.
  @MainActor
  init(_ item: AnyObject?, attribute: NSLayoutConstraint.Attribute, target: NSView) {
    self.attribute = Self.name(of: attribute)
    guard let item else {
      self.className = nil
      self.kind = "none"
      self.isTarget = false
      return
    }
    self.className = NSStringFromClass(object_getClass(item)!)
    self.isTarget = item === target
    if item is NSView {
      self.kind = "view"
    } else if item is NSLayoutGuide {
      self.kind = "layoutGuide"
    } else {
      self.kind = "other"
    }
  }

  /// The readable name of a layout attribute — a port of FLEX's `FLEXAttrName`.
  /// An unrecognized raw value falls through to `attr(n)`.
  private static func name(of attribute: NSLayoutConstraint.Attribute) -> String {
    switch attribute {
    case .left: return "left"
    case .right: return "right"
    case .top: return "top"
    case .bottom: return "bottom"
    case .leading: return "leading"
    case .trailing: return "trailing"
    case .width: return "width"
    case .height: return "height"
    case .centerX: return "centerX"
    case .centerY: return "centerY"
    case .lastBaseline: return "lastBaseline"
    case .firstBaseline: return "firstBaseline"
    case .notAnAttribute: return "notAnAttribute"
    @unknown default: return "attr(\(attribute.rawValue))"
    }
  }
}
