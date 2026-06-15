import AgentCLI
import Foundation
import UIToolCore

// SPEC: domain.uitool.ipc
/// The CLI's end of the IPC socket: connect to a session's
/// `/tmp/uitool-<pid>.sock`, perform the `ping` handshake (rejecting a schema
/// skew), and fetch the window-forest `Capture` the pure verbs run over. Effectful
/// — the policy stays in `UIToolCore`. Failures map to the closed `UIToolError`
/// vocabulary: a refused connect is `NOT_ATTACHED` (exit 4), a missing/garbled
/// response is `TIMEOUT` (exit 7), a version skew is `SCHEMA_MISMATCH` (exit 8).
public final class IPCClient {
  private let connection: LineConnection
  private var nextID = 1

  private init(connection: LineConnection) { self.connection = connection }

  /// Connect to the session socket. A refused connect — no listener, i.e. no live
  /// session — is `NOT_ATTACHED`, never a crash.
  public static func connect(socketPath: String) throws -> IPCClient {
    do {
      let fd = try UnixSocket.connect(path: socketPath)
      return IPCClient(connection: LineConnection(fd: fd))
    } catch {
      throw UIToolError.notAttached
    }
  }

  public func close() { UnixSocket.close(connection.fd) }

  /// The `ping` handshake; throws `SCHEMA_MISMATCH` when the server's schema
  /// version differs from the CLI's (the check that keeps the separately-built CLI
  /// and dylib from desyncing — [[domain.uitool.ipc]]).
  @discardableResult
  public func handshake() throws -> Ping {
    let response: WireResponse<Ping> = try roundTrip(op: "ping", maxDepth: nil)
    guard response.ok, let ping = response.data else {
      if let error = response.error { throw UIToolError.from(wire: error) }
      throw UIToolError.notAttached
    }
    guard ping.schemaVersion == Schema.version else {
      throw UIToolError.schemaMismatch(
        "CLI expects \"\(Schema.version)\", server reports \"\(ping.schemaVersion)\"")
    }
    return ping
  }

  /// Fetch the live window forest as a `Capture`. `maxDepth` nil fetches the full
  /// forest; the CLI's verbs navigate and prune over it (the dumb-server design,
  /// [[domain.uitool.server]]).
  public func fetchCapture(op: String = "windows", maxDepth: Int? = nil) throws -> Capture {
    let response: WireResponse<Capture> = try roundTrip(op: op, maxDepth: maxDepth)
    if let error = response.error { throw UIToolError.from(wire: error) }
    guard response.ok, let capture = response.data else { throw UIToolError.timeout }
    return capture
  }

  /// Tell the server to close and unlink its socket ([[command.uitool.detach]]).
  /// Returns whether it acknowledged closing.
  @discardableResult
  public func detach() throws -> Bool {
    let response: WireResponse<DetachAck> = try roundTrip(op: "detach", maxDepth: nil)
    return response.ok && (response.data?.closed ?? false)
  }

  /// Inspect a live object — resolve `node` server-side and read its ivar values +
  /// class reflection ([[command.uitool.inspect]]). `invoke` runs property getters;
  /// `match` narrows by name. A node that no longer resolves is `STALE_NODE` (exit 5).
  public func inspect(node: NodeID, invoke: Bool, match: String?) throws -> InspectResult {
    let request = WireRequest(
      id: nextID, op: "inspect", node: node.description, invoke: invoke, match: match)
    nextID += 1
    try connection.write(line: Output.line(request))
    guard let data = connection.readLine() else { throw UIToolError.timeout }
    let response = try JSONDecoder().decode(WireResponse<InspectResult>.self, from: data)
    if let error = response.error {
      if error.code == "STALE_NODE" { throw UIToolError.staleNode(node) }
      throw UIToolError.from(wire: error)
    }
    guard response.ok, let result = response.data else { throw UIToolError.timeout }
    return result
  }

  /// List the target's loaded classes matching `pattern` ([[command.uitool.classes]]).
  public func classList(pattern: String, limit: Int) throws -> ClassList {
    try send(WireRequest(id: nextID, op: "classes", match: pattern, limit: limit))
  }

  /// Reflect one loaded class by name ([[command.uitool.classes]]).
  public func classInfo(className: String) throws -> ClassInfo {
    try send(WireRequest(id: nextID, op: "classes", className: className))
  }

  /// Send a request and decode the expected payload, mapping a wire error.
  private func send<P: Codable & Sendable>(_ request: WireRequest) throws -> P {
    nextID += 1
    try connection.write(line: Output.line(request))
    guard let data = connection.readLine() else { throw UIToolError.timeout }
    let response = try JSONDecoder().decode(WireResponse<P>.self, from: data)
    if let error = response.error { throw UIToolError.from(wire: error) }
    guard response.ok, let payload = response.data else { throw UIToolError.timeout }
    return payload
  }

  /// Send one request, read one response line, decode it as the expected payload.
  /// A connection that closes before answering is `TIMEOUT` (the socket opened but
  /// the target never replied).
  private func roundTrip<P: Decodable & Sendable>(op: String, maxDepth: Int?) throws
    -> WireResponse<P>
  {
    let request = WireRequest(id: nextID, op: op, maxDepth: maxDepth)
    nextID += 1
    try connection.write(line: Output.line(request))
    guard let data = connection.readLine() else { throw UIToolError.timeout }
    return try JSONDecoder().decode(WireResponse<P>.self, from: data)
  }
}
