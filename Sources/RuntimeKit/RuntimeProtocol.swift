import ObjectiveC

// SPEC: domain.runtime.reflection
/// An eager, `Sendable` snapshot of an Objective-C `Protocol` — the metadata port
/// of FLEX's `FLEXProtocol`. Reads a live protocol off the runtime with
/// `protocol_getName` / `protocol_copyProtocolList` / `protocol_copyMethodDescriptionList`
/// / `protocol_copyPropertyList`, projecting each into plain data so the
/// description can cross actor and IPC boundaries without holding a `Protocol`
/// pointer.
///
/// Reflection sees the runtime, not the source: a protocol declared only in a
/// header but never realized in the process is invisible to `init?(named:)` and
/// to `conformances(of:)`.
public struct RuntimeProtocol: Sendable, Equatable {
  /// The protocol's name, from `protocol_getName`.
  public let name: String

  /// The names of every protocol this one directly conforms to (one level, not a
  /// recursively expanded tree), from `protocol_copyProtocolList`. Stored as names
  /// rather than nested `RuntimeProtocol`s to stay acyclic and `Sendable`.
  public let conformedProtocols: [String]

  /// Required **instance** method descriptions, from
  /// `protocol_copyMethodDescriptionList(_, required: true, instance: true, _)`.
  public let requiredInstanceMethods: [MethodDescription]

  /// Required **class** method descriptions, from
  /// `protocol_copyMethodDescriptionList(_, required: true, instance: false, _)`.
  public let requiredClassMethods: [MethodDescription]

  /// Optional **instance** method descriptions, from
  /// `protocol_copyMethodDescriptionList(_, required: false, instance: true, _)`.
  public let optionalInstanceMethods: [MethodDescription]

  /// Optional **class** method descriptions, from
  /// `protocol_copyMethodDescriptionList(_, required: false, instance: false, _)`.
  public let optionalClassMethods: [MethodDescription]

  /// The names of the protocol's declared properties, from
  /// `protocol_copyPropertyList`. Names only — the property *type* and attributes
  /// live in the sibling `RuntimeProperty`, so `RuntimeProtocol` stands alone.
  public let propertyNames: [String]

  /// Every required method (class then instance), folded as FLEX's
  /// `requiredMethods` does. Property getters/setters appear here too.
  public var requiredMethods: [MethodDescription] {
    requiredClassMethods + requiredInstanceMethods
  }

  /// Every optional method (class then instance), folded as FLEX's
  /// `optionalMethods` does.
  public var optionalMethods: [MethodDescription] {
    optionalClassMethods + optionalInstanceMethods
  }

  /// Snapshot a live `Protocol`, reading every field off the runtime eagerly.
  public init(_ proto: Protocol) {
    self.name = String(cString: protocol_getName(proto))
    self.conformedProtocols = Self.protocolNames(conformedBy: proto)
    self.requiredInstanceMethods = Self.methodDescriptions(
      of: proto, required: true, instance: true)
    self.requiredClassMethods = Self.methodDescriptions(
      of: proto, required: true, instance: false)
    self.optionalInstanceMethods = Self.methodDescriptions(
      of: proto, required: false, instance: true)
    self.optionalClassMethods = Self.methodDescriptions(
      of: proto, required: false, instance: false)
    self.propertyNames = Self.propertyNames(of: proto)
  }

  /// Look a protocol up by name via `objc_getProtocol` and snapshot it, or `nil`
  /// if no protocol with that name is registered with the runtime.
  public init?(named: String) {
    guard let proto = objc_getProtocol(named) else {
      return nil
    }
    self.init(proto)
  }

  /// Every protocol a class *directly* declares conformance to, via
  /// `class_copyProtocolList`, each snapshotted. Does not walk the superclass
  /// chain — it reflects what the class itself lists, matching the runtime call.
  public static func conformances(of cls: AnyClass) -> [RuntimeProtocol] {
    var count: UInt32 = 0
    guard let list = class_copyProtocolList(cls, &count) else {
      return []
    }
    // class_copyProtocolList returns a malloc'd C array the caller owns — same
    // free discipline as the protocol_copy* family. The element pointers are
    // unretained runtime-owned `Protocol`s; only the array itself is freed.
    defer { free(UnsafeMutableRawPointer(mutating: list)) }
    let buffer = UnsafeBufferPointer(start: list, count: Int(count))
    return buffer.map { RuntimeProtocol($0) }
  }

  // MARK: - Runtime readers

  /// The names of the protocols `proto` conforms to (one level).
  private static func protocolNames(conformedBy proto: Protocol) -> [String] {
    var count: UInt32 = 0
    guard let list = protocol_copyProtocolList(proto, &count) else {
      return []
    }
    defer { free(UnsafeMutableRawPointer(mutating: list)) }
    let buffer = UnsafeBufferPointer(start: list, count: Int(count))
    return buffer.map { String(cString: protocol_getName($0)) }
  }

  /// The method descriptions for one (required, instance) quadrant.
  private static func methodDescriptions(
    of proto: Protocol, required: Bool, instance: Bool
  ) -> [MethodDescription] {
    var count: UInt32 = 0
    guard
      let list = protocol_copyMethodDescriptionList(proto, required, instance, &count)
    else {
      return []
    }
    defer { free(list) }
    let buffer = UnsafeBufferPointer(start: list, count: Int(count))
    return buffer.compactMap { MethodDescription($0) }
  }

  /// The names of the protocol's declared properties.
  private static func propertyNames(of proto: Protocol) -> [String] {
    var count: UInt32 = 0
    guard let list = protocol_copyPropertyList(proto, &count) else {
      return []
    }
    defer { free(list) }
    let buffer = UnsafeBufferPointer(start: list, count: Int(count))
    return buffer.map { String(cString: property_getName($0)) }
  }
}

// SPEC: domain.runtime.reflection
/// One entry from a `struct objc_method_description` — the metadata port of FLEX's
/// `FLEXMethodDescription`. The `name` selector becomes `selector`; the `types`
/// C-string becomes `typeEncoding`.
///
/// FLEX's value also carries a `returnType` (the first encoding character) and an
/// `instance` flag. Neither is duplicated here: the return type is recoverable
/// from `typeEncoding.first`, and the instance/class split is preserved by *which*
/// `RuntimeProtocol` list a description appears in.
public struct MethodDescription: Sendable, Equatable {
  /// The demangled selector name, from `sel_getName(description.name)`.
  public let selector: String

  /// The method's full type encoding, from `description.types`.
  public let typeEncoding: String

  /// Snapshot a `struct objc_method_description`, or `nil` if the runtime left
  /// `name` null (an empty slot in the description list — FLEX asserts on this).
  init?(_ description: objc_method_description) {
    guard let name = description.name else {
      return nil
    }
    self.selector = String(cString: sel_getName(name))
    if let types = description.types {
      self.typeEncoding = String(cString: types)
    } else {
      self.typeEncoding = ""
    }
  }

  /// Construct a method description directly from its parts. Used by tests and any
  /// consumer assembling a description without a live runtime handle.
  public init(selector: String, typeEncoding: String) {
    self.selector = selector
    self.typeEncoding = typeEncoding
  }
}
