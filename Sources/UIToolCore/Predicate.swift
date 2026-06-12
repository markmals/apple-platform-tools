import Foundation

// SPEC: domain.uitool.selector
/// A parsed `--where` predicate — the bounded, **total** boolean expression
/// language from [[domain.uitool.selector]]. The grammar is comparisons over the
/// v1 attribute vocabulary, combined with `and` / `or` / `not`, plus the
/// pattern operators `*=` / `matches` and the class-of operator `~`.
///
/// "No recursion, bounded evaluation time, so a query can't hang the target": the
/// parsed form is a finite tree built once at parse time; `evaluate` is a single
/// pass over it. The depth is bounded by the source length (every nesting level
/// costs a `(` or a `not`), so a query can't loop or recurse unboundedly. Every
/// *usage* error — an unparseable expression, an unknown attribute, an uncompilable
/// regex — is caught at parse time, so `evaluate` itself never throws on a tree it
/// must resolve against a node.
public struct Predicate: Sendable {
  /// The parsed expression tree. Class-of (`~`) leaves need the tree to resolve the
  /// hierarchy, so a `Predicate` that uses `~` is evaluated against a node *in a
  /// tree*; a predicate without `~` evaluates against a bare node.
  let expression: Expression

  /// Parse a `--where` source string. Throws `BAD_PREDICATE` on a malformed
  /// expression, `UNKNOWN_FIELD` on an attribute the v1 vocabulary doesn't carry,
  /// and `BAD_SELECTOR` on an uncompilable `matches` pattern (the pattern is a
  /// regex, and a bad regex is a selector-grade usage error per the spec).
  public init(parsing source: String) throws {
    var parser = PredicateParser(source)
    self.expression = try parser.parse()
  }

  /// Evaluate the predicate against a node with **no** tree — usable only when the
  /// predicate carries no `~` class-of leaf. A `~` leaf with no tree resolves
  /// against the node's own class only (it cannot walk the hierarchy), which is the
  /// safe degenerate answer; callers that want hierarchy matching pass a tree.
  public func evaluate(_ node: Node) throws -> Bool {
    expression.evaluate(node, in: nil)
  }

  /// Evaluate the predicate against a node within a tree, so `~` resolves the full
  /// runtime class hierarchy.
  public func evaluate(_ node: Node, in tree: NodeTree) -> Bool {
    expression.evaluate(node, in: tree)
  }

  /// The canonical printed form of a number for string comparison — an integer
  /// prints without a decimal point (`childCount` reads `3`, not `3.0`), a
  /// fractional value with its natural decimals. Shared with `AttributeValue` so a
  /// `text *= '12'`-style match against a numeric attribute is consistent.
  static func printNumber(_ value: Double) -> String {
    if value.rounded() == value && abs(value) < 1e15 {
      return String(Int(value))
    }
    return String(value)
  }
}

// SPEC: domain.uitool.selector
/// The bounded `--where` expression tree. A finite algebraic type — a leaf is a
/// value comparison or a `~` class-of test; the connectives are `and`, `or`, and
/// `not`. Evaluation is a single recursive pass over this *parsed* structure,
/// whose depth the parser already bounded by the source length — there is no
/// unbounded recursion and no loop.
indirect enum Expression: Sendable {
  /// A value comparison: an attribute against an operator and operand.
  case comparison(Attribute, Comparison)
  /// `attr ~ 'NSClass'` — true when the node is of that class through the runtime
  /// hierarchy. Resolved against the tree; with no tree, only the node's own class.
  case classOf(Attribute, String)
  case and(Expression, Expression)
  case or(Expression, Expression)
  case not(Expression)

  /// Evaluate against a node (optionally within a tree). Total — no throw.
  func evaluate(_ node: Node, in tree: NodeTree?) -> Bool {
    switch self {
    case .comparison(let attribute, let test):
      return test.evaluate(attribute.value(of: node))
    case .classOf(let attribute, let className):
      return evaluateClassOf(attribute, className, node: node, tree: tree)
    case .and(let lhs, let rhs):
      return lhs.evaluate(node, in: tree) && rhs.evaluate(node, in: tree)
    case .or(let lhs, let rhs):
      return lhs.evaluate(node, in: tree) || rhs.evaluate(node, in: tree)
    case .not(let inner):
      return !inner.evaluate(node, in: tree)
    }
  }

  /// `~` resolution. `class ~ 'NSButton'` reads the node's class through the
  /// hierarchy; any other attribute on the left compares its string value to the
  /// class name exactly (a degenerate but total reading, since `~` is only
  /// meaningful on `class`). With no tree, hierarchy can't be walked, so only the
  /// node's own class is consulted.
  private func evaluateClassOf(
    _ attribute: Attribute, _ className: String, node: Node, tree: NodeTree?
  ) -> Bool {
    guard attribute == .classNameField else {
      return attribute.value(of: node).asString == className
    }
    if let tree { return MatchEngine.isKind(node, ofClass: className, in: tree) }
    return node.class == className
  }
}
