// SPEC: domain.uitool.selector
/// Structural navigation over the resolved forest, keyed by a projected `Node`'s
/// id — what the selector grammar needs that a single `Node` cannot answer alone:
/// a node's runtime superclass chain (for `~` hierarchy matching), and its parent
/// and ancestor ids (for descendant `space` and direct-child `>` combinators).
///
/// A default-projected `Node` carries `superclasses: nil` (it is an `--include`
/// facet), so `~` cannot read the chain off the node — it reads it off the
/// snapshot the tree still holds at that node's structural path. The selector
/// always evaluates *in a tree*, so this back-reference is always available; the
/// pure core never asks `~` to resolve against a detached node.
extension NodeTree {

  /// The runtime superclass chain for a node, off its backing snapshot (the
  /// immediate superclass up to `NSObject`, exclusive of the node's own class).
  /// Empty when the node's id is not in the forest — a node from another tree
  /// matches nothing through `~`, which is the safe, non-throwing answer for a
  /// structural traversal.
  func superclasses(of node: Node) -> [String] {
    resolvedNode(for: node)?.snapshot.superclasses ?? []
  }

  /// The parent node id of a projected node, or `nil` at a window root. Drives the
  /// direct-child `>` combinator.
  func parentID(of node: Node) -> NodeID? {
    resolvedNode(for: node)?.parent
  }

  /// The projected parent `Node` of a node, or `nil` at a window root — a shallow
  /// projection (depth 0) since selector combinators only read the parent's own
  /// fields, never its subtree. Drives ancestor walking in `Selector.matches`.
  func node(parentOf node: Node) -> Node? {
    guard let parentID = parentID(of: node), let parent = resolved(parentID) else { return nil }
    return Node.projecting(parent.snapshot, id: parent.id, parent: parent.parent, depth: 0)
  }

  /// Resolve a projected node back to the forest entry at its structural path.
  /// `nil` when the id parses but is absent (a node from a different walk).
  private func resolvedNode(for node: Node) -> ResolvedNode? {
    guard let id = NodeID(parsing: node.node) else { return nil }
    return resolved(id)
  }

  /// The forest entry at an id without the staleness gate — a structural lookup,
  /// not a deref. Selector traversal walks the live forest it was handed, so the
  /// class-echo check `lookup` applies (a recycled-slot guard for *held* ids) is
  /// not wanted here.
  private func resolved(_ id: NodeID) -> ResolvedNode? {
    entry(atPath: id.structuralPath)
  }
}
