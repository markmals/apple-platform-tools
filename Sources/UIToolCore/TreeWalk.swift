import RuntimeKit

// SPEC: command.uitool.tree
/// The structural-traversal primitive the `tree` and `find` verbs share: a flat
/// walk over the `NodeTree` forest that yields one [[domain.uitool.node]] per node,
/// in walk order. `tree` and `find` emit a **JSON-Lines stream** — one node record
/// per line, each carrying its own `parent` id — not a single nested object, so the
/// walk flattens: every emitted node is projected at depth 0 (no inlined
/// `children`), and a node sitting at the depth floor with children is marked
/// `truncated: true` + `childCount` per [[domain.uitool.node]]'s depth-cut contract.
enum TreeWalk {

  /// Walk a subtree rooted at `root` down `maxDepth` levels (inclusive of the root
  /// level), flattening to a list of depth-0-projected nodes in pre-order (root
  /// first, then z-ordered descendants). A node at the depth floor that still has
  /// children is emitted with `truncated: true` and its real `childCount`, and its
  /// descendants are not walked — the depth bound is honored exactly.
  static func nodes(
    from root: NodeTree.ResolvedNode, maxDepth: Int, include: IncludeFacets
  ) -> [Node] {
    var out: [Node] = []
    visit(
      snapshot: root.snapshot, id: root.id, parent: root.parent,
      remainingDepth: maxDepth, include: include, into: &out)
    return out
  }

  /// Every node in the whole forest, in window-then-pre-order — the candidate set
  /// `find` filters. Each is projected flat (depth 0) so a matched record carries no
  /// nested subtree; `find` returns the matches themselves, not their children.
  static func allNodes(of tree: NodeTree, include: IncludeFacets) -> [Node] {
    tree.rootEntries.flatMap { root -> [Node] in
      var out: [Node] = []
      visit(
        snapshot: root.snapshot, id: root.id, parent: root.parent,
        remainingDepth: Int.max, include: include, into: &out)
      return out
    }
  }

  /// Emit `snapshot` as a flat node, then recurse into z-ordered children while
  /// depth remains. At the depth floor (`remainingDepth <= 0`) a node with children
  /// is marked truncated and its subtree is skipped. `remainingDepth` counts levels
  /// still descendable *below* this node.
  private static func visit(
    snapshot: ViewSnapshot,
    id: NodeID,
    parent: NodeID?,
    remainingDepth: Int,
    include: IncludeFacets,
    into out: inout [Node]
  ) {
    let atFloor = remainingDepth <= 0
    let cut = atFloor && !snapshot.children.isEmpty
    out.append(
      flatNode(snapshot, id: id, parent: parent, include: include, truncated: cut))
    guard !atFloor else { return }

    var ordinals: [String: Int] = [:]
    for child in snapshot.children {
      let mnemonic = StructuralPath.mnemonic(forClass: child.runtimeClass)
      let ordinal = ordinals[mnemonic, default: 0]
      ordinals[mnemonic] = ordinal + 1
      let childID = id.appending(mnemonic: "\(mnemonic)\(ordinal)")
      visit(
        snapshot: child, id: childID, parent: id,
        remainingDepth: remainingDepth - 1, include: include, into: &out)
    }
  }

  /// Project one snapshot to a flat node — depth 0 so `children` is never inlined —
  /// overriding `truncated` to the walk's depth-cut decision (a node that has
  /// children but sits at the floor). `childCount` always reflects the real subview
  /// count, so a cut node stays distinguishable from a leaf.
  private static func flatNode(
    _ snapshot: ViewSnapshot, id: NodeID, parent: NodeID?, include: IncludeFacets, truncated: Bool
  ) -> Node {
    let projected = Node.projecting(snapshot, id: id, parent: parent, include: include, depth: 0)
    return projected.flattened(truncated: truncated)
  }
}

// SPEC: command.uitool.tree
extension Node {
  /// A copy of this node with no inlined `children` and an explicit `truncated`
  /// flag — the flat-stream shape `tree`/`find` emit. The default projection at
  /// depth 0 already drops `children`; this only re-stamps `truncated` to the
  /// walk's depth-cut decision so a leaf (`childCount: 0`) is never marked.
  func flattened(truncated: Bool) -> Node {
    Node(
      node: node, parent: parent, class: `class`, frame: frame, frameTopLeft: frameTopLeft,
      isFlipped: isFlipped, hidden: hidden, alpha: alpha, identifier: identifier, text: text,
      axRole: axRole, font: font, material: material, swiftUIBoundary: swiftUIBoundary,
      childCount: childCount, constraintsCount: constraintsCount, superclasses: superclasses,
      blendingMode: blendingMode, layer: layer, constraints: constraints, children: nil,
      truncated: truncated)
  }
}

// SPEC: command.uitool.find
extension NodeTree {
  /// Every node in the forest projected flat, in window-then-pre-order. The
  /// candidate set `find` filters; each is depth-0 (no nested children).
  func allNodes(include: IncludeFacets = []) -> [Node] {
    TreeWalk.allNodes(of: self, include: include)
  }
}
