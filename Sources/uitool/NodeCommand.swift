import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.node
/// `uitool node <app> --at NODE [--include …]` — deep-read exactly one located
/// node, the "read deep on the survivors" drill step. Resolves and validates `--at`
/// before any projection: a held id that no longer resolves (path gone, or recycled)
/// is `STALE_NODE` (exit 5), never a silent empty read. `--include` pulls the
/// structural facets the default projection omits (`class`/`constraints`/`layer`;
/// `frame` is a no-op; `ivars`/`props` are rejected as not-in-this-build). A scalar
/// query — one JSON object, not a stream — so it has no `_meta` and no trailing
/// envelope line.
struct Node: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "node",
    abstract: "Deep-read exactly one located node, pulling on-demand structural facets.")

  @Argument(help: "The attached target — pid or bundle id. Omit when reading --snapshot.")
  var app: String?

  @Option(name: .customLong("snapshot"), help: "Read a captured Capture JSON instead of attaching.")
  var snapshot: String?

  @Option(name: .customLong("at"), help: "Node id of the single node to read (e.g. 7:w0/cv).")
  var at: String

  @Option(
    name: .customLong("include"),
    help: "Comma-separated facets to pull (class,frame,constraints,layer).")
  var include: String?

  @Flag(
    name: .customLong("no-meta"),
    help: "Suppress the top-level sessionId for byte-stable output across sessions.")
  var noMeta = false

  func run() throws {
    do {
      guard let id = NodeID(parsing: at) else {
        throw UIToolError.badSelector("malformed node id: \(at)")
      }
      let facets = try Projection.includeFacets(splitInclude(include))
      let resolved = try loadTree(snapshot: snapshot, app: app)
      print(
        try Verbs.node(
          at: id, in: resolved.tree, include: facets,
          sessionId: noMeta ? nil : resolved.sessionId))
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}

/// Split the `--include` comma list into trimmed, non-empty tokens — the same
/// tokenization the shared `ReadOptions` group applies, repeated here because `node`
/// carries only `--include` (not the full stream-flag group).
private func splitInclude(_ raw: String?) -> [String] {
  guard let raw else { return [] }
  return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }
}
