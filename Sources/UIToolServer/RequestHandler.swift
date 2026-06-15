import AgentCLI
import AppKit
import RuntimeKit
import UIToolCore

// SPEC: domain.uitool.server
/// The injected server's request handler — the one piece of `uitool` that runs
/// inside the target. The **dumb forest-shipping** design: every cheap-read op
/// maps to one `AppKitWalker.snapshotApplicationWindows(maxDepth:)` call wrapped in
/// a `Capture`; `ping` returns the handshake. The CLI does all root-selection,
/// navigation, selector matching, projection, pruning, and node-id staleness over
/// the returned `Capture` via the pure verbs ([[domain.uitool.node]],
/// [[domain.uitool.selector]]) — so the foreign-process code holds no policy.
///
/// AppKit reads are main-thread-only, so the handler is `@MainActor`
/// ([[domain.uitool.ipc]] threading). The socket accept loop (a later slice) runs
/// off-main and marshals each request here under a bounded hop.
@MainActor
public enum RequestHandler {

  /// The closed read-op set. All three map to the same forest snapshot — the verb
  /// distinction is resolved CLI-side, never here.
  static let readOps: Set<String> = ["windows", "hierarchy", "find"]

  /// The `ping` handshake: the server's schema version (the CLI compares it to its
  /// own) and the session `epoch`.
  public static func ping(_ request: WireRequest, epoch: Int) -> WireResponse<Ping> {
    .success(id: request.id, Ping(schemaVersion: Schema.version, epoch: epoch))
  }

  /// A read: the live window forest snapshotted to the requested depth, wrapped in
  /// a `Capture` at the session `epoch` — the same envelope the offline source
  /// decodes from disk, so the CLI's verbs run over it unchanged.
  public static func read(_ request: WireRequest, epoch: Int) -> WireResponse<Capture> {
    let windows = AppKitWalker.snapshotApplicationWindows(maxDepth: request.maxDepth ?? .max)
    return .success(id: request.id, Capture(epoch: epoch, windows: windows))
  }

  /// The `inspect` value-fetching op ([[command.uitool.inspect]]): resolve the
  /// node id to a live object via [[domain.uitool.registry]] and reflect it. The
  /// re-walk is the staleness gate — a node id whose epoch is stale or whose path
  /// no longer resolves is `STALE_NODE` (exit 5), never a recycled read.
  public static func inspect(_ request: WireRequest, epoch: Int) -> WireResponse<InspectResult> {
    guard let nodeID = request.node else {
      return .failure(
        id: request.id,
        WireError(
          code: "BAD_SELECTOR", message: "inspect requires a node id",
          recover: "pass --at <node-id>"
        ))
    }
    let segments = nodeID.split(separator: ":", maxSplits: 1)
    guard segments.count == 2, let nodeEpoch = Int(segments[0]) else {
      return staleResponse(id: request.id, nodeID: nodeID)
    }
    let path = String(segments[1].split(separator: "#")[0])
    guard nodeEpoch == epoch, let view = LiveTreeResolver.resolve(structuralPath: path) else {
      return staleResponse(id: request.id, nodeID: nodeID)
    }
    let result = ObjectInspector.inspect(
      view, nodeID: nodeID, invoke: request.invoke ?? false, matching: matcher(for: request.match))
    return .success(id: request.id, result)
  }

  /// A name matcher from the `--match` regex, or `nil` (match all). An uncompilable
  /// pattern is caught CLI-side before the request; here it degrades to a substring
  /// match rather than crashing.
  private static func matcher(for pattern: String?) -> ((String) -> Bool)? {
    guard let pattern else { return nil }
    if let regex = try? Regex(pattern) {
      return { (try? regex.firstMatch(in: $0)) != nil }
    }
    return { $0.contains(pattern) }
  }

  private static func staleResponse(id: Int, nodeID: String) -> WireResponse<InspectResult> {
    .failure(
      id: id,
      WireError(
        code: "STALE_NODE", message: "node \(nodeID) no longer resolves",
        recover: "re-read the tree (windows/tree/find) for a fresh node id"))
  }

  /// Dispatch one decoded request to the JSON-Lines response the socket writes.
  /// `ping` / the read ops / `inspect` succeed; an op outside the closed vocabulary
  /// is a usage error (`BAD_SELECTOR`, exit 2 — [[domain.uitool.ipc]]), never a crash.
  /// (`classes` is dispatched off-main by `makeBoundedHandler`, not here.)
  public static func handle(_ request: WireRequest, epoch: Int) throws -> String {
    if request.op == "ping" {
      return try Output.line(ping(request, epoch: epoch))
    }
    if request.op == "inspect" {
      return try Output.line(inspect(request, epoch: epoch))
    }
    if readOps.contains(request.op) {
      return try Output.line(read(request, epoch: epoch))
    }
    let error = WireError(
      code: "BAD_SELECTOR",
      message: "unknown op: \(request.op)",
      recover: "use one of: ping, windows, hierarchy, find")
    return try Output.line(WireResponse<Capture>.failure(id: request.id, error))
  }
}
