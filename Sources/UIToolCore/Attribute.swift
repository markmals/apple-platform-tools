// SPEC: domain.uitool.selector
/// The v1 attribute vocabulary both the structural-selector `[attr op value]` form
/// and the `--where` predicate language address — sourced verbatim from
/// [[domain.uitool.selector]] "v1 attribute vocabulary", all backed by a field on
/// [[domain.uitool.node]]. The set is intentionally small and additive within a
/// major: a path that names nothing here is an `UNKNOWN_FIELD` usage error, never
/// silently treated as a zero-match.
///
/// An attribute resolves a projected `Node` to a typed scalar. The two query
/// languages share this one resolver so the addressable surface — and the
/// unknown-field rejection — can never drift between them.
enum Attribute: String, CaseIterable {
  case classNameField = "class"
  case identifier
  case axRole
  case text
  case title
  case frameX = "frame-x"
  case frameY = "frame-y"
  case frameW = "frame-w"
  case frameH = "frame-h"
  case hidden
  case alpha
  case isFlipped
  case swiftUIBoundary
  case childCount
  case material

  /// Resolve an attribute path or throw `UNKNOWN_FIELD`. The throwing lookup is the
  /// boundary check: a `[bogus=…]` selector token or a `where bogus = …` operand is
  /// rejected here before any node is matched.
  static func resolve(_ path: String) throws -> Attribute {
    guard let attribute = Attribute(rawValue: path) else {
      throw UIToolError.unknownField(path)
    }
    return attribute
  }

  /// The attribute's value on a node, as a comparison scalar. `title` and `text`
  /// both surface the node's string handle — on a view node the control's string,
  /// on a window root the window title the projection folded into `text`. A `nil`
  /// optional (no identifier, no text, no material) reads as `.absent`, distinct
  /// from an empty string, so `identifier = ''` does not match an unset id.
  func value(of node: Node) -> AttributeValue {
    switch self {
    case .classNameField: return .string(node.class)
    case .identifier: return .optionalString(node.identifier)
    case .axRole: return .optionalString(node.axRole)
    case .text, .title: return .optionalString(node.text)
    case .frameX: return .number(node.frame.x)
    case .frameY: return .number(node.frame.y)
    case .frameW: return .number(node.frame.width)
    case .frameH: return .number(node.frame.height)
    case .hidden: return .bool(node.hidden)
    case .alpha: return .number(node.alpha)
    case .isFlipped: return .bool(node.isFlipped)
    case .swiftUIBoundary: return .bool(node.swiftUIBoundary)
    case .childCount: return .number(Double(node.childCount))
    case .material: return .optionalString(node.material)
    }
  }
}

// SPEC: domain.uitool.selector
/// A resolved attribute scalar — the typed operand a comparison or substring test
/// runs against. Kept tiny and total: a value is a string, a number, a bool, or
/// `.absent` (an unset optional). String/number/bool form the three comparison
/// domains; `.absent` never compares true except against the empty-handling rules
/// the operators encode.
enum AttributeValue: Equatable {
  case string(String)
  case optionalString(String?)
  case number(Double)
  case bool(Bool)
  case absent

  /// Normalize `.optionalString(nil)` to `.absent` so a single switch covers both
  /// "no such facet" and "the facet is nil" without every operator re-checking.
  var normalized: AttributeValue {
    if case .optionalString(let inner) = self {
      return inner.map(AttributeValue.string) ?? .absent
    }
    return self
  }

  /// The string projection a substring (`*=`) or regex (`matches`) test reads. A
  /// number folds to its node-printed form, a bool to `true`/`false`; `.absent`
  /// has no string and never matches a pattern.
  var asString: String? {
    switch normalized {
    case .string(let value): return value
    case .number(let value): return Predicate.printNumber(value)
    case .bool(let value): return value ? "true" : "false"
    case .absent: return nil
    case .optionalString: return nil  // unreachable after normalize
    }
  }
}
