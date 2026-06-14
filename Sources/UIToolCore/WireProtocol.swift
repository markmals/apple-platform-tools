// SPEC: domain.uitool.ipc
/// The JSON-Lines request/response types spoken over the `uitool` IPC socket —
/// shared by the CLI client and the injected [[domain.uitool.server]], so the two
/// ends cannot drift on the shape. The *wire* need not be byte-stable (the CLI's
/// stdout is); these types exist so encode/decode is one definition, not two.

/// The int protocol version carried as `v` on every request and response —
/// distinct from the semver `schemaVersion` string ([[domain.uitool.ipc]]). A `v`
/// the other end does not speak is a hard error; v1 is `1`.
public enum WireProtocol {
  public static let version = 1
}

// SPEC: domain.uitool.ipc
/// One request on the socket. The op vocabulary is closed; v1 carries the cheap-
/// read ops (`windows` / `hierarchy` / `find`, which all map to one depth-bounded
/// forest snapshot server-side — [[domain.uitool.server]]) and the `ping`
/// handshake. The server reads only `op` and `maxDepth`; the CLI computes
/// `maxDepth` per verb and does all navigation/matching over the response.
public struct WireRequest: Codable, Equatable, Sendable {
  public let v: Int
  public let id: Int
  public let op: String
  /// The depth the forest snapshot is bounded to; `nil` means unbounded.
  public let maxDepth: Int?

  public init(id: Int, op: String, maxDepth: Int? = nil, v: Int = WireProtocol.version) {
    self.v = v
    self.id = id
    self.op = op
    self.maxDepth = maxDepth
  }
}

// SPEC: domain.uitool.ipc
/// The handshake payload `ping` returns: the server's schema version (the CLI
/// compares it to its own and raises a mismatch, [[command.uitool.attach]]) and
/// the session `epoch` (the wire form of node-id's `sessionEpoch`).
public struct Ping: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let epoch: Int

  public init(schemaVersion: String, epoch: Int) {
    self.schemaVersion = schemaVersion
    self.epoch = epoch
  }
}

// SPEC: domain.uitool.ipc
/// A wire error object: a code from the closed [[domain.uitool.ipc]] vocabulary, a
/// one-line message, and a one-line recovery hint — never a stack trace.
public struct WireError: Codable, Equatable, Sendable {
  public let code: String
  public let message: String
  public let recover: String

  public init(code: String, message: String, recover: String) {
    self.code = code
    self.message = message
    self.recover = recover
  }
}

// SPEC: domain.uitool.ipc
/// One response on the socket. Success carries a typed `data` payload (a `Capture`
/// for a read, a `Ping` for the handshake); failure carries `error`.
/// `schemaVersion` is on every payload and is never suppressible. The CLI knows
/// which op it sent, so it decodes the matching `Payload`; on `ok == false`,
/// `data` is absent and `error` is set.
public struct WireResponse<Payload: Codable & Sendable>: Codable, Sendable {
  public let v: Int
  public let id: Int
  public let ok: Bool
  public let schemaVersion: String
  public let data: Payload?
  public let error: WireError?

  public init(
    id: Int, ok: Bool, data: Payload?, error: WireError? = nil, v: Int = WireProtocol.version
  ) {
    self.v = v
    self.id = id
    self.ok = ok
    self.schemaVersion = Schema.version
    self.data = data
    self.error = error
  }

  public static func success(id: Int, _ data: Payload) -> WireResponse {
    WireResponse(id: id, ok: true, data: data)
  }

  public static func failure(id: Int, _ error: WireError) -> WireResponse {
    WireResponse(id: id, ok: false, data: nil, error: error)
  }
}
