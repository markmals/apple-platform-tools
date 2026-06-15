// SPEC: command.uitool.classes
/// The result of `classes --match` — the loaded class names matching the pattern,
/// capped and sorted ([[command.uitool.classes]]).
public struct ClassList: Codable, Sendable, Equatable {
  public let match: String
  /// The total number of matches before the `--limit` cap.
  public let count: Int
  public let truncated: Bool
  public let names: [String]

  public init(match: String, count: Int, truncated: Bool, names: [String]) {
    self.match = match
    self.count = count
    self.truncated = truncated
    self.names = names
  }
}

// SPEC: command.uitool.classes
/// The result of `classes --class` — one class's declared shape (metadata only, no
/// instance, no values). `loaded` is false when the name is not a loaded class.
public struct ClassInfo: Codable, Sendable, Equatable {
  public let `class`: String
  public let loaded: Bool
  /// The inheritance chain (superclass up to NSObject); the reflected members are
  /// declared, not inherited ([[domain.runtime.reflection]]).
  public let superclasses: [String]
  public let ivars: [ClassIvar]
  public let properties: [String]
  public let methods: [String]
  public let classMethods: [String]
  public let protocols: [String]

  public init(
    class cls: String, loaded: Bool, superclasses: [String], ivars: [ClassIvar],
    properties: [String], methods: [String], classMethods: [String], protocols: [String]
  ) {
    self.class = cls
    self.loaded = loaded
    self.superclasses = superclasses
    self.ivars = ivars
    self.properties = properties
    self.methods = methods
    self.classMethods = classMethods
    self.protocols = protocols
  }
}

// SPEC: command.uitool.classes
/// One declared ivar's metadata (name + `@encode` type) — no value, no offset
/// (class-level reflection, no instance).
public struct ClassIvar: Codable, Sendable, Equatable {
  public let name: String
  public let type: String

  public init(name: String, type: String) {
    self.name = name
    self.type = type
  }
}
