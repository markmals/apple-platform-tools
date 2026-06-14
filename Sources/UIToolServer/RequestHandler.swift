import AgentCLI
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

  /// Dispatch one decoded request to the JSON-Lines response the socket writes.
  /// `ping` and the read ops succeed; an op outside the closed vocabulary is a
  /// usage error (`BAD_SELECTOR`, exit 2 — [[domain.uitool.ipc]]), never a crash.
  public static func handle(_ request: WireRequest, epoch: Int) throws -> String {
    if request.op == "ping" {
      return try Output.line(ping(request, epoch: epoch))
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
