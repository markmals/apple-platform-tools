// SPEC: command.uitool.inspect
/// The result of an `inspect` — one live object's ivar values and class reflection.
/// The server reads it off the live object (it must: a snapshot can't carry live
/// memory); the CLI projects and emits it. Values are normalized to plain JSON with
/// **no raw pointers** and no invoked `-description`: a scalar is its value, an
/// object is `{class, node?}` ([[command.uitool.inspect]] value representation).
public struct InspectResult: Codable, Sendable, Equatable {
  /// The node id this object was inspected through ([[domain.uitool.node-id]]).
  public let node: String
  /// The object's real runtime class (`object_getClass`).
  public let `class`: String
  /// The instance variables and their current values (safe memory reads).
  public let ivars: [InspectedIvar]
  /// The declared instance properties; `value` is present only under `--invoke`.
  public let properties: [InspectedProperty]
  /// The adopted protocol names (class reflection).
  public let protocols: [String]
  /// The declared instance method selectors (class reflection).
  public let methods: [String]

  public init(
    node: String, class cls: String, ivars: [InspectedIvar], properties: [InspectedProperty],
    protocols: [String], methods: [String]
  ) {
    self.node = node
    self.class = cls
    self.ivars = ivars
    self.properties = properties
    self.protocols = protocols
    self.methods = methods
  }
}

// SPEC: command.uitool.inspect
/// One instance variable: its name, `@encode` type, and current value (a scalar, an
/// object `{class, node?}`, or null). Read from memory — no target code runs.
public struct InspectedIvar: Codable, Sendable, Equatable {
  public let name: String
  public let type: String
  public let value: JSONValue

  public init(name: String, type: String, value: JSONValue) {
    self.name = name
    self.type = type
    self.value = value
  }
}

// SPEC: command.uitool.inspect
/// One declared property: name, `@encode` type, readonly flag, and — only when
/// `--invoke` ran its getter — the value the getter returned.
public struct InspectedProperty: Codable, Sendable, Equatable {
  public let name: String
  public let type: String
  public let readonly: Bool
  public let value: JSONValue?

  public init(name: String, type: String, readonly: Bool, value: JSONValue? = nil) {
    self.name = name
    self.type = type
    self.readonly = readonly
    self.value = value
  }
}
