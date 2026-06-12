import AgentCLI

// SPEC: domain.uitool.ipc
/// The schema version stamped on every `uitool` payload — a semver **string**,
/// distinct from the int protocol version `v` on the wire. It is in *every*
/// response and is never suppressible by `--no-meta` ([[domain.uitool.ipc]]
/// invariants); additive changes only within a major.
public enum Schema {
  public static let version = "1.0.0"
}

// SPEC: domain.uitool.ipc
/// The list/stream `_meta` summary per [[domain.uitool.ipc]]: `returned` is the
/// record count emitted, `totalMatched` the full match count regardless of
/// `--limit`, and `truncated` the single canonical "more exist past the
/// limit/depth" flag (never a second `limitHit`). A scalar verb (`node`) carries
/// no `_meta`; only list/stream verbs do.
public struct ResponseMeta: Codable, Equatable, Sendable {
  public let returned: Int
  public let truncated: Bool
  public let totalMatched: Int

  public init(returned: Int, truncated: Bool, totalMatched: Int) {
    self.returned = returned
    self.truncated = truncated
    self.totalMatched = totalMatched
  }
}

// SPEC: domain.uitool.ipc
/// The trailing envelope line a list/stream verb emits after its node records.
/// `schemaVersion` is mandatory and never stripped; `sessionId` (the wire form of
/// node-id's `sessionEpoch`) and `_meta` are present unless `--no-meta` strips
/// them, so output is byte-identical across sessions. The custom encoding keeps
/// the JSON keys exactly `schemaVersion` / `sessionId` / `_meta` and omits the two
/// suppressible keys entirely (not as `null`) when absent.
public struct ResponseEnvelope: Codable, Equatable, Sendable {
  /// Always present, never suppressible — the mandatory semver string.
  public let schemaVersion: String
  /// The attach session id; `nil` when `--no-meta` strips it (or no session id is
  /// available from an offline capture).
  public let sessionId: String?
  /// The list/stream summary; `nil` when `--no-meta` strips it.
  public let meta: ResponseMeta?

  public init(sessionId: String?, meta: ResponseMeta?) {
    self.schemaVersion = Schema.version
    self.sessionId = sessionId
    self.meta = meta
  }

  /// Assemble a list verb's trailing envelope. With `noMeta`, `sessionId` and
  /// `_meta` are dropped so only `schemaVersion` remains; otherwise both are
  /// carried (a nil `sessionId` — an offline capture with no session — still
  /// omits the key rather than emitting `null`).
  public static func forList(
    sessionId: String?, meta: ResponseMeta, noMeta: Bool
  ) -> ResponseEnvelope {
    noMeta
      ? ResponseEnvelope(sessionId: nil, meta: nil)
      : ResponseEnvelope(sessionId: sessionId, meta: meta)
  }

  /// The single compact JSON-Lines record for this envelope, key-sorted and
  /// slash-unescaped through the shared AgentCLI encoder.
  public func line() throws -> String {
    try Output.line(self)
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case sessionId
    case meta = "_meta"
  }
}
