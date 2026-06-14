import AgentCLI
import ArgumentParser
import UIToolCore
import UIToolIPC

// SPEC: command.uitool.detach
/// `uitool detach <app>` — end an inspection session: tell the injected server to
/// close and unlink its socket, after which a read to the same target refuses with
/// `NOT_ATTACHED`. Idempotent — detaching a target with no live session is a clean
/// success (exit 0), never an error. The launched/attached process keeps running;
/// detach removes only the inspection bridge ([[command.uitool.detach]]).
struct Detach: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "detach",
    abstract: "End an inspection session (the target keeps running).")

  @Argument(help: "The target, by pid or bundle id, as passed to launch/attach.")
  var app: String

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  @Flag(
    name: .customLong("no-meta"), help: "Suppress the top-level sessionId for byte-stable output.")
  var noMeta = false

  func run() throws {
    let pid = SessionSnapshotSource.resolvePID(for: app)
    var wasAttached = false
    var sessionId: String?

    if let pid, let client = try? IPCClient.connect(socketPath: UnixSocket.path(forPID: pid)) {
      defer { client.close() }
      sessionId = (try? client.handshake().epoch).map(String.init)
      try? client.detach()
      wasAttached = true
    }

    let result = DetachResult(
      ok: true,
      target: .init(pid: pid.map(Int.init), bundleId: nil),
      channel: "closed",
      wasAttached: wasAttached,
      sessionId: noMeta ? nil : sessionId)
    print(pretty ? try Output.json(result) : try Output.line(result))
  }
}

// SPEC: command.uitool.detach
/// The `detach` result object: the channel is closed, `wasAttached` distinguishes a
/// real teardown from the idempotent no-op, and `sessionId` (when present) names the
/// session that was torn down.
private struct DetachResult: Encodable {
  let ok: Bool
  let target: Target
  let channel: String
  let wasAttached: Bool
  let sessionId: String?

  struct Target: Encodable {
    let pid: Int?
    let bundleId: String?
  }
}
