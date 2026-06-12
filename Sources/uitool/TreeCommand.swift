import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.tree
/// `uitool tree <app> --at NODE [--depth N] [--where EXPR]` — walk a depth-bounded
/// subtree, projecting each node to `--fields` and filtering emitted nodes by
/// `--where`. The walk descends `--depth` levels below the root; a branch cut by
/// the depth limit carries `truncated: true` + `childCount`. `--limit` caps the
/// emitted records; `--count-only` sizes without bodies. A stale `--at` is exit 5.
/// In the offline MVP, `--at` is required (no live key-window auto-root yet).
struct Tree: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "tree",
    abstract: "Walk a depth-bounded subtree of the view hierarchy from a chosen root.")

  @Argument(help: "The attached target — pid or bundle id. Omit when reading --snapshot.")
  var app: String?

  @Option(name: .customLong("at"), help: "Node id to root the walk at (e.g. 7:w0/cv).")
  var at: String

  @Option(name: .customLong("depth"), help: "Levels to descend below the root, inclusive.")
  var depth = 2

  @Option(name: .customLong("where"), help: "Predicate filtering which walked nodes are emitted.")
  var predicate: String?

  @OptionGroup var options: ReadOptions

  func run() throws {
    do {
      guard let root = NodeID(parsing: at) else {
        throw UIToolError.badSelector("malformed node id: \(at)")
      }
      let parsed = try predicate.map { try Predicate(parsing: $0) }
      let resolved = try loadTree(snapshot: options.snapshot, app: app)
      let result = try Verbs.tree(
        at: root, in: resolved.tree, maxDepth: depth, fields: options.fieldList,
        where: parsed, limit: options.limit, countOnly: options.countOnly,
        include: try options.includeFacets())
      try runStream(result, sessionId: resolved.sessionId, noMeta: options.noMeta)
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}
