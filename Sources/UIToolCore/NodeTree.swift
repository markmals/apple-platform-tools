import RuntimeKit

// SPEC: domain.uitool.node-id
/// The snapshot forest indexed by structural path — the pure-core stand-in for
/// the injected server's live object registry. Built eagerly from the app's
/// `[WindowSnapshot]` at one epoch: every node is assigned its [[domain.uitool.node-id]]
/// during the walk (`w<n>` for window n, `cv` for its content view, then a
/// class-mnemonic + same-class-sibling ordinal per descendant), and the resolved
/// snapshot plus its parent id are stored under that path.
///
/// `resolve` is the staleness gate. In the pure core a held id resolves iff its
/// epoch matches and its structural path is still present in the forest; a path
/// that no longer resolves returns `STALE_NODE`, never a silent fallback to a
/// recycled node. Because each path segment encodes its node's class *mnemonic*,
/// a class change at a position generally changes the path and so surfaces as a
/// stale path. The finer **recorded-class echo** the spec mentions — catching a
/// recycle to a *different class with the same mnemonic* across turns — needs the
/// minting class persisted per id, which only the injected server's registry
/// holds; it is deferred with that half, not faked here with a self-comparison.
public struct NodeTree: Sendable {
  /// The epoch every minted id carries — bumped on `attach`.
  public let epoch: Int

  /// The resolved snapshot for each node, keyed by its full structural path.
  private let nodesByPath: [String: ResolvedNode]

  /// The app's top-level windows, retained in `NSApp.windows` order so the
  /// `windows` verb can project window-level records (`title`/`key`/`main`/screen
  /// `frame`) the view forest does not carry.
  private let windows: [WindowSnapshot]

  /// One entry in the index: the snapshot and its parent's id (`nil` at a root).
  public struct ResolvedNode: Sendable {
    public let snapshot: ViewSnapshot
    public let id: NodeID
    public let parent: NodeID?
  }

  /// Build the index from the app's top-level windows at `epoch`. Child windows
  /// are not separate roots — they hang under their parent in the snapshot — so
  /// only the top-level array seeds window indices.
  public init(windows: [WindowSnapshot], epoch: Int) {
    self.epoch = epoch
    self.windows = windows
    var index: [String: ResolvedNode] = [:]
    for (windowIndex, window) in windows.enumerated() {
      let windowID = NodeID(epoch: epoch, structuralPath: StructuralPath.window(windowIndex))
      Self.indexWindow(window, id: windowID, into: &index)
    }
    self.nodesByPath = index
  }

  /// The forest entry at a structural path, **without** the held-id staleness gate
  /// — a raw structural lookup over the live forest the tree was built from. Used
  /// by selector traversal, which walks the tree it was handed (the class-echo
  /// guard in `lookup` is a recycled-slot check for *held* ids across turns, not
  /// wanted for in-tree navigation).
  func entry(atPath path: String) -> ResolvedNode? {
    nodesByPath[path]
  }

  /// Look a held id up without throwing — the resolved node iff its epoch matches
  /// and its path is present; `nil` otherwise. The non-throwing twin of `resolve`,
  /// for callers that want to branch on presence themselves.
  public func lookup(_ id: NodeID) -> ResolvedNode? {
    guard id.epoch == epoch else { return nil }
    return nodesByPath[id.structuralPath]
  }

  /// Resolve a held id or throw `STALE_NODE`. The deref gate: a path the forest no
  /// longer carries (a wrong epoch, or a structure that shifted so the path is
  /// gone) is stale, and there is no safe fallback (the code-quality "no silent
  /// fallback" rule and the spec's "never dereference a recycled pointer").
  public func resolve(_ id: NodeID) throws -> ResolvedNode {
    guard let resolved = lookup(id) else { throw UIToolError.staleNode(id) }
    return resolved
  }

  /// Project the app's top-level windows as window-level records — the `windows`
  /// verb's list, in `NSApp.windows` order (the `w<n>` index basis). Each record is
  /// a window root (`w<n>`, `parent` null) carrying the base node fields plus the
  /// window-only `title`/`key`/`main` and the window's screen frame — not a view
  /// node. An empty window set yields an empty list (a valid `NO_WINDOWS` empty
  /// result, not a failure).
  public func windowRecords() -> [WindowRecord] {
    windows.enumerated().map { index, window in
      WindowRecord(window, id: NodeID(epoch: epoch, structuralPath: StructuralPath.window(index)))
    }
  }

  /// The content-view root id of each window, in window order.
  private var rootIDs: [NodeID] {
    nodesByPath.values
      .filter { $0.parent == nil }
      .map(\.id)
      .sorted { $0.structuralPath < $1.structuralPath }
  }

  /// The window-root entry of each window, in window order — the seeds the `find`
  /// verb's whole-tree enumeration and the `tree` walk start from. A forest read,
  /// not a deref: no staleness gate (in-tree navigation walks the live forest it
  /// was built from).
  var rootEntries: [ResolvedNode] {
    rootIDs.map { nodesByPath[$0.structuralPath]! }
  }

  /// Walk a window: its content view becomes the `w<n>/cv` root, then the subtree
  /// is indexed recursively.
  private static func indexWindow(
    _ window: WindowSnapshot, id windowID: NodeID, into index: inout [String: ResolvedNode]
  ) {
    guard let contentView = window.contentView else { return }
    let contentID = windowID.appending(mnemonic: StructuralPath.contentView)
    indexSubtree(contentView, id: contentID, parent: nil, into: &index)
  }

  /// Index a view subtree: record this node, then recurse into z-ordered children,
  /// minting each child's `<mnemonic><ordinal>` segment.
  private static func indexSubtree(
    _ snapshot: ViewSnapshot, id: NodeID, parent: NodeID?, into index: inout [String: ResolvedNode]
  ) {
    index[id.structuralPath] = ResolvedNode(snapshot: snapshot, id: id, parent: parent)

    var ordinals: [String: Int] = [:]
    for child in snapshot.children {
      let mnemonic = StructuralPath.mnemonic(forClass: child.runtimeClass)
      let ordinal = ordinals[mnemonic, default: 0]
      ordinals[mnemonic] = ordinal + 1
      let childID = id.appending(mnemonic: "\(mnemonic)\(ordinal)")
      indexSubtree(child, id: childID, parent: id, into: &index)
    }
  }
}
