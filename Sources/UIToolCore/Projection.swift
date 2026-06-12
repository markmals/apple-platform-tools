import AgentCLI
import Foundation
import RuntimeKit

// SPEC: domain.uitool.node
/// Field selection (`--fields`) and facet selection (`--include`) over a projected
/// [[domain.uitool.node]], plus the deterministic encoding both feed into.
///
/// `--fields` is a projection **path list** (`class,frame,font.family`) over a
/// node's JSON, NOT full jq — full jq is a footgun the selector spec deliberately
/// excludes. A path that names no field on the node is an `UNKNOWN_FIELD` usage
/// error, never silently dropped. `--include` turns the structural facets on
/// (`superclasses` via `class`, `blendingMode`, `layer`, `constraints`); the
/// value-fetching facets (`ivars`/`props`) require the injection half and are
/// rejected as not-available-in-this-build, never silently dropped.
///
/// Determinism — 1-dp rounding, sorted keys — comes from AgentCLI's `Output`
/// encoder over the already-rounded `Node`; this layer never hand-rolls JSON.
public enum Projection {

  /// Parse the `--include` token list into the structural `IncludeFacets`, or throw.
  /// `frame` is a no-op (the frame fields are already default), accepted but adding
  /// nothing. `ivars`/`props` are deferred value-fetching facets — rejected as a
  /// usage error naming the facet and that it needs the injection half. Any other
  /// token is an unknown facet (also a usage error).
  public static func includeFacets(_ tokens: [String]) throws -> IncludeFacets {
    var facets: IncludeFacets = []
    for token in tokens.map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
      switch token {
      case "class": facets.insert(.superclasses)
      case "blendingMode": facets.insert(.blendingMode)
      case "layer": facets.insert(.layer)
      case "constraints": facets.insert(.constraints)
      case "frame": break  // No-op: frame fields are already default-projection.
      case "ivars", "props":
        throw UIToolError.badSelector(
          "facet '\(token)' requires the injection half and is not available in this build")
      default:
        throw UIToolError.badSelector("unknown --include facet '\(token)'")
      }
    }
    return facets
  }

  /// Encode a node for stream output (one JSON-Lines record), narrowed to `fields`
  /// when a non-empty path list is given. With no fields the whole node encodes;
  /// with fields, only the named paths survive, in sorted-key order. An unknown
  /// path is `UNKNOWN_FIELD`.
  public static func line(_ node: Node, fields: [String]) throws -> String {
    try Output.line(try projected(node, fields: fields))
  }

  /// Encode a node for scalar output (one pretty JSON object), narrowed to `fields`.
  public static func json(_ node: Node, fields: [String]) throws -> String {
    try Output.json(try projected(node, fields: fields))
  }

  /// Encode the `node` verb's single-node result, enforcing the requested-facet
  /// contract: a facet the caller asked for but the node lacks is emitted as
  /// **`null`, never omitted**, so the agent distinguishes "asked, absent" from "not
  /// asked". Swift's synthesized encoder drops a `nil` optional, so an unbacked
  /// `--include layer` would otherwise vanish; this re-stamps each requested facet's
  /// key to `null` when it is absent. (`--include frame`/`class` carry no nullable
  /// field of their own — `frame` is already default, `class` adds `superclasses`.)
  /// `sessionId` (when given) is stamped as a top-level key — the `node` verb is a
  /// scalar payload, so the IPC envelope's `sessionId` rides on the object itself
  /// (there is no trailing `_meta` line for a single-node read). `--no-meta` passes
  /// `nil` here for byte-stable output across sessions.
  public static func nodeJSON(_ node: Node, include: IncludeFacets, sessionId: String? = nil)
    throws -> String
  {
    var object = try encodeToObject(node)
    for (facet, field) in facetFields where include.contains(facet) {
      if object[field] == nil { object[field] = .null }
    }
    if let sessionId { object["sessionId"] = .string(sessionId) }
    return try Output.json(ProjectedRecord(object))
  }

  /// The node field each nullable `--include` facet populates — used to re-stamp an
  /// absent requested facet as explicit `null`.
  private static let facetFields: [(IncludeFacets, String)] = [
    (.superclasses, "superclasses"),
    (.blendingMode, "blendingMode"),
    (.layer, "layer"),
    (.constraints, "constraints"),
  ]

  /// The node as an `Encodable` payload narrowed to `fields`. With no fields the
  /// node passes through verbatim (the AgentCLI encoder still sorts keys and the
  /// node already carries 1-dp values); with fields, only the named top-level
  /// paths and dotted sub-paths survive. Validates every path against the node's
  /// field vocabulary first, so a single bad path fails the whole projection
  /// before any record is emitted.
  static func projected(_ node: Node, fields: [String]) throws -> ProjectedRecord {
    let object = try encodeToObject(node)
    guard !fields.isEmpty else { return ProjectedRecord(object) }
    var picked: [String: JSONValue] = [:]
    // The node id is the handle every record is addressed by — always retain it,
    // even when --fields does not name it, so a narrowed record stays referenceable.
    if let nodeID = object["node"] { picked["node"] = nodeID }
    for path in fields {
      picked.merge([topKey(of: path): try pick(path, from: object)]) { existing, new in
        existing.merging(new)
      }
    }
    return ProjectedRecord(picked)
  }

  /// The top-level key a `--fields` path projects under — `font.family` lands in
  /// the result under `font` (with only `family` inside), so two paths into the
  /// same facet merge rather than clobber.
  private static func topKey(of path: String) -> String {
    String(path.split(separator: ".", maxSplits: 1).first ?? "")
  }

  /// Resolve one `--fields` path. The **head** segment is validated against the
  /// node's field vocabulary (`Node.fieldNames`), so a misspelled top-level field is
  /// `UNKNOWN_FIELD` — even when the instance happens to carry it as `nil` (an
  /// omitted-from-JSON optional is still a *valid* field, projected as `null`). A
  /// leaf path returns the encoded value (or `null` when the optional was nil); a
  /// dotted path descends into the facet and returns a single-key object so sibling
  /// paths into the same facet merge.
  private static func pick(_ path: String, from object: [String: JSONValue]) throws -> JSONValue {
    let segments = path.split(separator: ".").map(String.init)
    guard let head = segments.first, Node.fieldNames.contains(head) else {
      throw UIToolError.unknownField(path)
    }
    return try descend(Array(segments.dropFirst()), in: object[head] ?? .null, path: path)
  }

  /// Project the remaining dotted sub-path into an already-resolved facet value. A
  /// nil/absent facet projects `null` (the field is valid, the value absent); a
  /// present object requires the next sub-key to exist (else `UNKNOWN_FIELD`); a
  /// scalar with sub-path remaining is an unknown deeper path. The returned shape is
  /// a single-key object per level so sibling paths into the same facet merge.
  private static func descend(
    _ segments: [String], in value: JSONValue, path: String
  ) throws -> JSONValue {
    guard let next = segments.first else { return value }
    guard case .object(let nested) = value else {
      // A dotted path into a nil/absent facet names a valid field with no value.
      if case .null = value { return .object([next: .null]) }
      throw UIToolError.unknownField(path)
    }
    guard let child = nested[next] else { throw UIToolError.unknownField(path) }
    return .object([next: try descend(Array(segments.dropFirst()), in: child, path: path)])
  }

  /// Re-decode a node through JSON into a key/value map — the basis for path
  /// projection. Goes through the AgentCLI-shaped encoder so the values match the
  /// wire exactly (1-dp frames, the node's own omit-nil shape). The node is always
  /// a JSON object, so the cast is total.
  private static func encodeToObject(_ node: Node) throws -> [String: JSONValue] {
    let data = try JSONEncoder().encode(node)
    guard case .object(let object) = try JSONDecoder().decode(JSONValue.self, from: data) else {
      throw UIToolError.unknownField("<node>")
    }
    return object
  }
}
