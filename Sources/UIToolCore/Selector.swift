import Foundation

// SPEC: domain.uitool.selector
/// A parsed CSS-like **structural** selector — the `find` query language from
/// [[domain.uitool.selector]]. A selector is a chain of *compound* selectors
/// joined by combinators: descendant (a space) and direct-child (`>`). A compound
/// selector is a class token (matched through the runtime hierarchy via `~`), a
/// wildcard `*`, and zero or more `[attr op value]` attribute predicates, all of
/// which must hold on one node.
///
/// `matches(_:in:)` answers the *rightmost* (key) compound against the candidate,
/// then walks the ancestor chain to satisfy the combinators to its left — so
/// `NSScrollView NSTableView` matches a table that has a scroll-view ancestor, and
/// `NSStackView > NSTextField` only a field whose *immediate* parent is a stack
/// view. Class matching honors the runtime class hierarchy (`NSControl` matches
/// `NSButton`), the headline capability AX cannot offer.
public struct Selector: Sendable {
  /// The compound selectors, left-to-right as written (`a b > c` → `[a, b, c]`).
  let compounds: [CompoundSelector]
  /// The combinator joining compound *i+1* to compound *i*; one fewer than
  /// `compounds`. `.descendant` for a space, `.child` for `>`.
  let combinators: [Combinator]

  /// Parse a selector string or throw a usage error: `BAD_SELECTOR` for malformed
  /// structure or an uncompilable `[attr matches …]` (compiled eagerly here so a
  /// bad pattern is rejected before any node is touched), `UNKNOWN_FIELD` for an
  /// `[attr …]` naming no v1 attribute.
  public init(parsing input: String) throws {
    var parser = SelectorParser(input)
    let (compounds, combinators) = try parser.parse()
    self.compounds = compounds
    self.combinators = combinators
  }

  /// `true` when `node` matches this selector within `tree`. The key compound (the
  /// rightmost) must hold on the node itself; each combinator to the left is
  /// satisfied against the node's ancestors.
  public func matches(_ node: Node, in tree: NodeTree) -> Bool {
    guard let key = compounds.last else { return false }
    guard key.matches(node, in: tree) else { return false }
    return matchesAncestors(of: node, upTo: compounds.count - 1, in: tree)
  }

  /// Satisfy the combinators left of the key compound by walking ancestors. Each
  /// compound from `index-1` down must match an ancestor; `.child` demands the
  /// immediate parent, `.descendant` any ancestor at or above. A greedy right-to-
  /// left walk is exact for this bounded grammar (no `*` combinator backtracking).
  private func matchesAncestors(of node: Node, upTo index: Int, in tree: NodeTree) -> Bool {
    var currentNode = node
    var compoundIndex = index - 1
    while compoundIndex >= 0 {
      let compound = compounds[compoundIndex]
      let combinator = combinators[compoundIndex]
      guard
        let ancestor = nearestAncestor(
          of: currentNode, matching: compound, combinator: combinator, in: tree)
      else { return false }
      currentNode = ancestor
      compoundIndex -= 1
    }
    return true
  }

  /// The ancestor of `node` that satisfies `compound` under `combinator`: for
  /// `.child`, only the immediate parent (and only if it matches); for
  /// `.descendant`, the nearest matching ancestor walking upward.
  private func nearestAncestor(
    of node: Node, matching compound: CompoundSelector, combinator: Combinator, in tree: NodeTree
  ) -> Node? {
    var parentNode = tree.node(parentOf: node)
    switch combinator {
    case .child:
      guard let parent = parentNode, compound.matches(parent, in: tree) else { return nil }
      return parent
    case .descendant:
      while let candidate = parentNode {
        if compound.matches(candidate, in: tree) { return candidate }
        parentNode = tree.node(parentOf: candidate)
      }
      return nil
    }
  }
}

// SPEC: domain.uitool.selector
/// How two adjacent compound selectors relate: a descendant (any ancestor) or a
/// direct child (the immediate parent).
enum Combinator: Sendable {
  case descendant
  case child
}

// SPEC: domain.uitool.selector
/// One compound selector — a class token (or `*`) plus its `[attr op value]`
/// predicates. Every part must hold on a single node for the compound to match.
struct CompoundSelector: Sendable {
  /// The class name to match through the runtime hierarchy (`~`), or `nil` for the
  /// wildcard `*` (matches any class).
  let className: String?
  /// The `[attr op value]` predicates, conjoined; all must hold.
  let attributes: [AttributeSelector]

  /// `true` when the node is of this compound's class (through the hierarchy) and
  /// satisfies every attribute predicate.
  func matches(_ node: Node, in tree: NodeTree) -> Bool {
    if let className, !MatchEngine.isKind(node, ofClass: className, in: tree) {
      return false
    }
    return attributes.allSatisfy { $0.matches(node) }
  }
}

// SPEC: domain.uitool.selector
/// One `[attr op value]` predicate inside a compound selector — `[title*="Inbox"]`,
/// `[frame-w>200]`, `[hidden=false]`. Resolves its attribute against the node and
/// applies a comparison. The substring form compiles its `Regex` at parse time, so
/// an uncompilable pattern (only possible via the regex engine, never `*=`) is a
/// `BAD_SELECTOR` rejected before any node is matched.
struct AttributeSelector: Sendable {
  let attribute: Attribute
  let test: Comparison

  /// `true` when the attribute's value on `node` satisfies the comparison.
  func matches(_ node: Node) -> Bool {
    test.evaluate(attribute.value(of: node))
  }
}
