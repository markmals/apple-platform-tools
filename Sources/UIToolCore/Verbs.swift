import AgentCLI
import RuntimeKit

// SPEC: command.uitool.windows
/// The four pure read verbs over an app's window list (`[WindowSnapshot]`) and the
/// `NodeTree` indexed from it — `windows`, `tree`, `find`, `node`. Each is the
/// pure decision core the (deferred) injected server and CLI wrap: it takes
/// snapshot VALUES, projects [[domain.uitool.node]]s, applies the selector /
/// predicate / depth / limit logic, and returns an encodable result. No transport,
/// no AppKit, no JSON hand-rolling — determinism comes from AgentCLI's encoder over
/// the already-rounded nodes.
///
/// The canonical loop the surface is built around: **locate few** (`find`) →
/// **project narrow** (`--fields`) → **read deep on survivors** (`node`), with
/// `windows`/`tree` for structural orientation and `--count-only` to size a query
/// before paying for the bodies.
public enum Verbs {

  /// A streamed verb's result — the projected records (already narrowed to
  /// `--fields`) plus the IPC `_meta` summary. `returned` is the record count;
  /// `truncated` is the single canonical "more exist past the limit/depth" flag;
  /// `totalMatched` is the full count the verb matched regardless of `--limit`.
  public struct StreamResult: Sendable {
    public let lines: [String]
    public let returned: Int
    public let truncated: Bool
    public let totalMatched: Int
  }

  /// The default result cap shared by `find` and `tree`: 50 records. The default
  /// exists so a too-broad selector or an unexpectedly wide level can never blow the
  /// agent's context on the first call — raise it deliberately with `--limit N`.
  public static let defaultLimit = 50

  // MARK: - windows

  // SPEC: command.uitool.windows
  /// List the app's top-level windows as window-level [[command.uitool.windows]]
  /// records — the cheapest query in the surface (a fixed, tiny payload, no
  /// descendant walk). Each entry is a window root (`w<n>`, parent null) carrying
  /// the base node fields plus the window-only `title`/`key`/`main` and the window's
  /// screen frame — *not* a view node, and not its content view. Records are in
  /// `NSApp.windows` order (the `wN` index basis). The record shape is fixed (no
  /// `--fields`/`--include`). An empty window set yields an empty list — a valid
  /// `NO_WINDOWS` empty result, never a failure.
  public static func windows(_ tree: NodeTree) throws -> StreamResult {
    let records = tree.windowRecords()
    let lines = try records.map { try Output.line($0) }
    return StreamResult(
      lines: lines, returned: lines.count, truncated: false, totalMatched: records.count)
  }

  // MARK: - tree

  // SPEC: command.uitool.tree
  /// Walk a depth-bounded subtree rooted at `at`, projecting each node to `fields`,
  /// optionally filtering emitted nodes by `where`. The walk descends `maxDepth`
  /// levels below the root (inclusive of the root level); a node with children at
  /// the depth floor carries `truncated: true` + `childCount` and omits `children`.
  /// `predicate` selects which walked nodes are **emitted** — it does not prune the
  /// walk, so a deep match is never hidden behind a shallow non-match. `--limit`
  /// caps the emitted records; `--count-only` returns the matched count with no
  /// bodies. A stale `at` throws `STALE_NODE`.
  public static func tree(
    at root: NodeID,
    in tree: NodeTree,
    maxDepth: Int,
    fields: [String] = [],
    where predicate: Predicate? = nil,
    limit: Int = defaultLimit,
    countOnly: Bool = false,
    include: IncludeFacets = []
  ) throws -> StreamResult {
    let resolved = try tree.resolve(root)
    let walked = TreeWalk.nodes(from: resolved, maxDepth: maxDepth, include: include)
    return try summarize(
      walked, in: tree, fields: fields, where: predicate, limit: limit, countOnly: countOnly)
  }

  // MARK: - find

  // SPEC: command.uitool.find
  /// Locate the nodes across the whole tree matching `selector` (a class glob /
  /// structural selector) and/or `where` (a predicate), in structural order. At
  /// least one constraint is required upstream; both compose (selector narrows by
  /// class/structure, `where` adds predicate constraints over the survivors).
  /// `--limit` (default 50) caps the returned records but never the reported
  /// `totalMatched`; `--count-only` returns only the count, no bodies — "size it
  /// before you pay." A 0-match query is a valid empty result, not an error.
  public static func find(
    in tree: NodeTree,
    selector: Selector? = nil,
    where predicate: Predicate? = nil,
    limit: Int = defaultLimit,
    countOnly: Bool = false,
    fields: [String] = [],
    include: IncludeFacets = []
  ) throws -> StreamResult {
    // A bare `find` with no selector and no predicate would match every node — the
    // exact unbounded slurp the surface exists to discourage. At least one
    // constraint is required (the spec's "locate few"); reject an unconstrained find.
    guard selector != nil || predicate != nil else {
      throw UIToolError.badSelector("find requires a selector or a --where predicate")
    }
    let matches = tree.allNodes(include: include).filter { node in
      let bySelector = selector?.matches(node, in: tree) ?? true
      let byWhere = predicate?.evaluate(node, in: tree) ?? true
      return bySelector && byWhere
    }
    return try emit(matches, fields: fields, limit: limit, countOnly: countOnly)
  }

  // MARK: - node

  // SPEC: command.uitool.node
  /// Deep-read exactly one node resolved by `at`, carrying the requested `--include`
  /// facets. Resolves and validates `at` before any projection — a held id that no
  /// longer resolves (path gone, or recycled to a different class) throws
  /// `STALE_NODE`, never a silent empty read. Reads exactly one node — never its
  /// subtree. Requested-but-inapplicable facets project as `null`, not omitted, so
  /// the agent distinguishes "asked, absent" from "not asked".
  public static func node(at id: NodeID, in tree: NodeTree, include: IncludeFacets = []) throws
    -> String
  {
    let resolved = try tree.resolve(id)
    let node = Node.projecting(
      resolved.snapshot, id: resolved.id, parent: resolved.parent, include: include, depth: 0)
    return try Projection.nodeJSON(node, include: include)
  }

  // MARK: - shared

  /// Apply a `--where` filter to a set of walked nodes (the tree verb's
  /// emit-not-prune semantics), then cap and project. The walk already produced the
  /// nodes in walk order; the predicate drops non-matchers from the result without
  /// re-pruning their descendants (those were walked independently).
  private static func summarize(
    _ walked: [Node],
    in tree: NodeTree,
    fields: [String],
    where predicate: Predicate?,
    limit: Int,
    countOnly: Bool
  ) throws -> StreamResult {
    let matches = walked.filter { predicate?.evaluate($0, in: tree) ?? true }
    return try emit(matches, fields: fields, limit: limit, countOnly: countOnly)
  }

  /// Cap a match list to `limit`, project each survivor to `fields`, and assemble
  /// the `_meta`. Under `--count-only` no bodies are projected — only the count
  /// crosses. `truncated` is true exactly when the cap hid matches.
  private static func emit(
    _ matches: [Node], fields: [String], limit: Int, countOnly: Bool
  ) throws -> StreamResult {
    let total = matches.count
    guard !countOnly else {
      return StreamResult(lines: [], returned: 0, truncated: false, totalMatched: total)
    }
    let capped = Array(matches.prefix(max(0, limit)))
    let lines = try capped.map { try Projection.line($0, fields: fields) }
    return StreamResult(
      lines: lines, returned: lines.count, truncated: total > lines.count, totalMatched: total)
  }
}
