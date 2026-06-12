import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.find
/// `uitool find <app> [<selector>] [--where EXPR]` — the "locate few" entry point.
/// Matches nodes across the whole tree by a structural class selector and/or a
/// `--where` predicate, in structural order. At least one constraint is required;
/// `Verbs.find` rejects a bare `find` (the unbounded slurp the surface exists to
/// discourage). `--limit` (default 50) caps the returned records but never
/// `totalMatched`; `--count-only` sizes before paying. A 0-match query is a valid
/// empty result (exit 0), not an error.
struct Find: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "find",
    abstract: "Locate nodes matching a class selector and/or a --where predicate.")

  @Argument(help: "The attached target — pid or bundle id. Omit when reading --snapshot.")
  var app: String?

  @Argument(help: "A structural class selector (e.g. 'NSScrollView NSTableView').")
  var selector: String?

  @Option(name: .customLong("where"), help: "Predicate adding constraints over the survivors.")
  var predicate: String?

  @OptionGroup var options: ReadOptions

  func run() throws {
    do {
      let parsedSelector = try selector.map { try Selector(parsing: $0) }
      let parsedPredicate = try predicate.map { try Predicate(parsing: $0) }
      let resolved = try loadTree(snapshot: options.snapshot, app: app)
      let result = try Verbs.find(
        in: resolved.tree, selector: parsedSelector, where: parsedPredicate,
        limit: options.limit, countOnly: options.countOnly, fields: options.fieldList,
        include: try options.includeFacets())
      try runStream(result, sessionId: resolved.sessionId, noMeta: options.noMeta)
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}
