import Foundation

// SPEC: domain.uitool.node
/// A minimal JSON tree — the intermediate form `--fields` projection narrows over.
/// A projected `Node` is re-decoded into this so a path list can pick top-level and
/// dotted sub-paths without hand-rolling per-field selection on the `Node` struct.
/// `Codable` so it round-trips through the AgentCLI `Output` encoder (sorted keys,
/// unescaped slashes); numbers are carried raw because the node already rounded its
/// floats to 1 dp before this layer ever sees them.
public enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// Deep-merge two objects so two `--fields` paths into the same facet combine
  /// rather than clobber — `font.family` then `font.size` yields one `font` object
  /// with both keys. Only objects merge recursively; any other pair takes `other`
  /// (a leaf path and a dotted path into the same head don't co-occur in practice).
  func merging(_ other: JSONValue) -> JSONValue {
    guard case .object(let lhs) = self, case .object(let rhs) = other else { return other }
    var merged = lhs
    for (key, value) in rhs {
      merged[key] = merged[key].map { $0.merging(value) } ?? value
    }
    return .object(merged)
  }
}

// SPEC: domain.uitool.node
/// The encodable payload a `--fields`-narrowed projection emits — a bag of
/// `JSONValue`s keyed by field name. Encoding through AgentCLI's `Output` sorts the
/// keys, so the projected record is byte-stable for a given field set.
struct ProjectedRecord: Encodable {
  private let fields: [String: JSONValue]

  init(_ fields: [String: JSONValue]) {
    self.fields = fields
  }

  func encode(to encoder: Encoder) throws {
    try fields.encode(to: encoder)
  }
}
