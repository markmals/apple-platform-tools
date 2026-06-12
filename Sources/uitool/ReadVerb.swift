import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: domain.uitool.ipc
/// The flags every read verb (`tree` / `find` / `node`) shares, plus the offline
/// `--snapshot` source selector. `@OptionGroup`-ed into each verb so the surface
/// stays uniform: same `--fields` / `--include` / `--limit` / `--count-only` /
/// `--no-meta` semantics everywhere, parsed once. (`windows` has a fixed record
/// shape and carries only `--no-meta`, so it does not use this group.)
struct ReadOptions: ParsableArguments {
  @Option(name: .customLong("snapshot"), help: "Read a captured Capture JSON instead of attaching.")
  var snapshot: String?

  @Option(
    name: .customLong("fields"), help: "Comma-separated projection paths (e.g. node,class,frame).")
  var fields: String?

  @Option(
    name: .customLong("include"),
    help: "Comma-separated facets to pull (class,frame,constraints,layer).")
  var include: String?

  @Option(name: .customLong("limit"), help: "Cap on returned records.")
  var limit: Int = Verbs.defaultLimit

  @Flag(name: .customLong("count-only"), help: "Return only the match count, no bodies.")
  var countOnly = false

  @Flag(name: .customLong("no-meta"), help: "Suppress sessionId and _meta for byte-stable output.")
  var noMeta = false

  /// The `--fields` path list, split on commas with blanks dropped; empty when the
  /// flag is omitted (the full default projection).
  var fieldList: [String] {
    splitList(fields)
  }

  /// The parsed `--include` facets, or a usage error on an unknown / deferred token.
  func includeFacets() throws -> IncludeFacets {
    try Projection.includeFacets(splitList(include))
  }
}

// SPEC: domain.uitool.ipc
/// The window forest a read verb runs over, paired with the session id its records
/// belong to. The session id is the wire form of the capture's epoch (the
/// [[domain.uitool.node-id]] `sessionEpoch`), so the offline snapshot and the
/// handles read out of it agree on which session minted them. An offline capture's
/// epoch *is* its session.
struct ResolvedTree {
  let tree: NodeTree
  let sessionId: String
}

// SPEC: command.uitool.windows
/// Resolve a read verb's `<app>` / `--snapshot` flags to a loaded forest: pick the
/// source ([[command.uitool.windows]] `resolveSource`), `load()` its `Capture`
/// (offline file now; the gated live session throws `NOT_ATTACHED`), and index a
/// `NodeTree` at the capture's epoch. The single point where a read verb crosses
/// from flags to data — a verb never decodes a `Capture` or builds a tree itself.
func loadTree(snapshot: String?, app: String?) throws -> ResolvedTree {
  let capture = try resolveSource(snapshot: snapshot, app: app).load()
  let tree = NodeTree(windows: capture.windows, epoch: capture.epoch)
  return ResolvedTree(tree: tree, sessionId: String(capture.epoch))
}

/// Split a comma list flag into trimmed, non-empty tokens.
private func splitList(_ raw: String?) -> [String] {
  guard let raw else { return [] }
  return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }
}

// SPEC: domain.uitool.ipc
/// Print a streamed verb's result on the IPC wire shape: each already-encoded node
/// record line, then — unless `--no-meta` — the trailing envelope line carrying
/// `schemaVersion` + `sessionId` + `_meta`. `schemaVersion` is on every record
/// line via the pure core's projection; this only appends the summary. Under
/// `--count-only` the result has no record lines, so just the envelope crosses.
/// The session id is the wire form of the capture's epoch (node-id's
/// `sessionEpoch`); an offline capture's epoch is its session.
func runStream(_ result: Verbs.StreamResult, sessionId: String?, noMeta: Bool) throws {
  for line in result.lines { print(line) }
  let meta = ResponseMeta(
    returned: result.returned, truncated: result.truncated, totalMatched: result.totalMatched)
  let envelope = ResponseEnvelope.forList(sessionId: sessionId, meta: meta, noMeta: noMeta)
  print(try envelope.line())
}
