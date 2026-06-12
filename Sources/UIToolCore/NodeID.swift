// SPEC: domain.uitool.node-id
/// A stable, collision-safe handle for a live object across many agent turns —
/// `"<sessionEpoch>:<structuralPath>#<ptrTag>"` per [[domain.uitool.node-id]].
///
/// The pure core mints the epoch + structural path; it never carries a pointer
/// tag (the live pointer is a server concern, "for collision detection only,
/// never re-lookup"), so `pointerTag` is `nil` here and the stringification omits
/// the `#<tag>` suffix. The structural path is root-relative and **legible** — a
/// breadcrumb a reader can often mutate by hand (`tr3` → `tr4`) without a
/// round-trip — which the spec calls out as a context-budget feature.
public struct NodeID: Sendable, Codable, Hashable, CustomStringConvertible {
  /// Bumped on `attach`; detects stale handles across re-attach.
  public let epoch: Int

  /// Root-relative path of class-mnemonic + same-class-sibling-ordinal segments,
  /// e.g. `w0/cv/tv0/tr3/c1`. The window segment is `w<n>`; a window's content
  /// view is the fixed mnemonic `cv`; every other descendant is a class mnemonic
  /// plus its ordinal among siblings of the same class.
  public let structuralPath: String

  /// A short hash of the object pointer, **for collision detection only**. Always
  /// `nil` in the pure core — the live pointer never crosses the purity boundary.
  public let pointerTag: String?

  public init(epoch: Int, structuralPath: String, pointerTag: String? = nil) {
    self.epoch = epoch
    self.structuralPath = structuralPath
    self.pointerTag = pointerTag
  }

  /// `"<epoch>:<path>"`, plus `"#<tag>"` only when a pointer tag is supplied.
  public var description: String {
    let base = "\(epoch):\(structuralPath)"
    guard let pointerTag else { return base }
    return "\(base)#\(pointerTag)"
  }
}

extension NodeID {
  /// The single id is its `description`. A `Node` carries this string, never the
  /// struct, so the projected JSON reads `"node": "7:w0/cv/tv0"`.
  public var stringValue: String { description }
}

extension NodeID {
  /// A node id encodes as its flat string form, not as an object — the wire shape
  /// in [[domain.uitool.node]] is a single `string`, and the breadcrumb is only
  /// legible as one token.
  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let parsed = NodeID(parsing: raw) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "malformed node id: \(raw)"))
    }
    self = parsed
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  /// Parse `"<epoch>:<path>"` (optionally `"#<tag>"`) back into a `NodeID`. The
  /// inverse of `description`; rejects a missing/non-integer epoch.
  public init?(parsing raw: String) {
    guard let colon = raw.firstIndex(of: ":") else { return nil }
    guard let epoch = Int(raw[..<colon]) else { return nil }
    let rest = raw[raw.index(after: colon)...]
    if let hash = rest.firstIndex(of: "#") {
      self.init(
        epoch: epoch,
        structuralPath: String(rest[..<hash]),
        pointerTag: String(rest[rest.index(after: hash)...]))
    } else {
      self.init(epoch: epoch, structuralPath: String(rest))
    }
  }
}
