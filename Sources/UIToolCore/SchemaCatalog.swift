// SPEC: command.uitool.schema
/// The tool's output contract as authored data — the machine-readable twin of
/// [[domain.uitool.node]] / [[command.uitool.inspect]] that `uitool schema` prints.
/// Static and pure; keep it in step with the `Node` / `InspectResult` types and the
/// node spec's field table (a test asserts the node record's field names match the
/// projected node's keys).
public enum SchemaCatalog {

  public static func contract() -> SchemaContract {
    SchemaContract(
      schemaVersion: Schema.version,
      exitCodes: exitCodes,
      records: [
        "node": nodeRecord,
        "window": windowRecord,
        "inspect": inspectRecord,
      ])
  }

  /// The closed exit-code map the agent branches on ([[domain.uitool.ipc]]).
  private static let exitCodes: [String: String] = [
    "0": "ok (a zero-match query is still 0)",
    "2": "usage / BAD_SELECTOR / UNKNOWN_FIELD / BAD_PREDICATE",
    "3": "APP_NOT_RUNNING / APP_NOT_FOUND",
    "4": "NOT_ATTACHED / injection failed",
    "5": "STALE_NODE",
    "6": "precondition failed",
    "7": "TIMEOUT",
    "8": "schema-version mismatch",
  ]

  /// The view-node record (`windows`/`tree`/`find`/`node`) — the default projection
  /// plus the `--include` facets ([[domain.uitool.node]]).
  private static let nodeRecord = RecordSchema(
    description: "a view-tree node (windows/tree/find/node)",
    fields: [
      .init("node", "string", default: true, description: "stable node id"),
      .init(
        "parent", "string|null", default: true, description: "parent node id; null at a window root"
      ),
      .init("class", "string", default: true, description: "real runtime class (object_getClass)"),
      .init(
        "frame", "{x,y,w,h}", default: true,
        description: "raw NSView coords (bottom-left origin), 1dp"),
      .init(
        "frameTopLeft", "{x,y,w,h}", default: true,
        description: "normalized top-left, window-relative"),
      .init("isFlipped", "bool", default: true, description: "the view's isFlipped"),
      .init("hidden", "bool", default: true, description: "isHidden"),
      .init("alpha", "number", default: true, description: "alphaValue, 1dp"),
      .init(
        "identifier", "string|null", default: true, description: "NSUserInterfaceItemIdentifier"),
      .init("text", "string|null", default: true, description: "the view's text content"),
      .init("axRole", "string|null", default: true, description: "accessibility role"),
      .init("font", "Font|null", default: true, description: "decomposed NSFont snapshot"),
      .init("material", "string|null", default: true, description: "NSVisualEffectView.material"),
      .init("swiftUIBoundary", "bool", default: true, description: "true at an NSHostingView"),
      .init("childCount", "int", default: true, description: "number of subviews"),
      .init(
        "constraintsCount", "int", default: true, description: "number of touching constraints"),
      .init("children", "Node[]", default: true, description: "present only within --depth"),
      .init(
        "truncated", "bool", default: true,
        description: "true when children were omitted at the depth bound"),
      .init(
        "superclasses", "string[]", default: false, include: "class",
        description: "runtime class chain"),
      .init(
        "blendingMode", "string|null", default: false, include: "blendingMode",
        description: "visual-effect blending mode"),
      .init(
        "layer", "Layer|null", default: false, include: "layer", description: "CALayer snapshot"),
      .init(
        "constraints", "Constraint", default: false, include: "constraints",
        description: "the touching NSLayoutConstraints"),
    ])

  /// The window record (`windows`) — window-level facts a view node has no enclosing
  /// view for.
  private static let windowRecord = RecordSchema(
    description: "a top-level window (windows)",
    fields: [
      .init("node", "string", default: true, description: "stable window node id (w<n>)"),
      .init("parent", "null", default: true, description: "always null — a window is a root"),
      .init("class", "string", default: true, description: "real runtime class"),
      .init("title", "string", default: true, description: "window title"),
      .init("key", "bool", default: true, description: "is the key window"),
      .init("main", "bool", default: true, description: "is the main window"),
      .init("frame", "{x,y,w,h}", default: true, description: "screen frame, 1dp"),
    ])

  /// The `inspect` record — a live object's values + reflection ([[command.uitool.inspect]]).
  private static let inspectRecord = RecordSchema(
    description: "a live object's ivars + reflection (inspect)",
    fields: [
      .init("node", "string", default: true, description: "the node id inspected"),
      .init("class", "string", default: true, description: "real runtime class"),
      .init(
        "ivars", "[{name,type,value}]", default: true,
        description: "ivar values (safe memory reads)"),
      .init(
        "properties", "[{name,type,readonly,value?}]", default: true,
        description: "declared properties; value only with --invoke"),
      .init("protocols", "string[]", default: true, description: "adopted protocol names"),
      .init(
        "methods", "string[]", default: true, description: "declared instance method selectors"),
    ])
}

// SPEC: command.uitool.schema
public struct SchemaContract: Encodable, Sendable {
  public let schemaVersion: String
  public let exitCodes: [String: String]
  public let records: [String: RecordSchema]
}

// SPEC: command.uitool.schema
public struct RecordSchema: Encodable, Sendable {
  public let description: String
  public let fields: [FieldSchema]
}

// SPEC: command.uitool.schema
public struct FieldSchema: Encodable, Sendable {
  public let name: String
  public let type: String
  public let `default`: Bool
  public let include: String?
  public let description: String

  init(
    _ name: String, _ type: String, default isDefault: Bool, include: String? = nil,
    description: String
  ) {
    self.name = name
    self.type = type
    self.default = isDefault
    self.include = include
    self.description = description
  }
}
