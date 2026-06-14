import Foundation
import ObjectiveC
import RuntimeKit
import UIToolCore

// SPEC: command.uitool.inspect
/// Reflect one live object into an `InspectResult` — the value-fetching read
/// `RuntimeKit` deliberately leaves out (`RuntimeIvar` ports ivar *metadata* only;
/// reading the *value* is here, where `inspect` uses it). Runs on the target main
/// thread. Ivar reads are **safe** (memory only, no target code) and the default;
/// property-getter invocation is the gated `--invoke` path (Slice 2).
///
/// Safety ([[command.uitool.inspect]]): a `RuntimeSafety`-unsafe class is reflected
/// for metadata but its ivars are not read; an unsafe ivar is skipped. Values carry
/// **no raw pointers** — an object ivar becomes `{class, node?}`, a scalar its value.
@MainActor
public enum ObjectInspector {

  /// Reflect `object`. `matching` narrows ivars/properties by name; `resolveNode`
  /// maps a referenced object to its node id when it is a registered view (Slice 2
  /// passes the registry; until then it returns nil).
  public static func inspect(
    _ object: NSObject,
    nodeID: String,
    matching: ((String) -> Bool)? = nil,
    resolveNode: (NSObject) -> String? = { _ in nil }
  ) -> InspectResult {
    let cls: AnyClass = object_getClass(object) ?? type(of: object)
    let mirror = RuntimeMirror(reflecting: object)
    let matches = matching ?? { _ in true }

    let ivars = readIvars(of: object, cls: cls, matches: matches, resolveNode: resolveNode)
    let properties = mirror.properties
      .filter { matches($0.name) }
      .map {
        InspectedProperty(name: $0.name, type: $0.typeEncoding, readonly: $0.attributes.isReadOnly)
      }

    return InspectResult(
      node: nodeID,
      class: mirror.className,
      ivars: ivars,
      properties: properties,
      protocols: mirror.protocols.map(\.name).sorted(),
      methods: mirror.methods.map(\.selectorName).sorted())
  }

  // MARK: - ivar values

  /// The object's ivars up the class chain (stopping before `NSObject`), each with
  /// its current value. Skips unsafe classes/ivars and names that don't match.
  private static func readIvars(
    of object: NSObject, cls: AnyClass, matches: (String) -> Bool,
    resolveNode: (NSObject) -> String?
  ) -> [InspectedIvar] {
    var result: [InspectedIvar] = []
    var current: AnyClass? = cls
    while let owner = current, owner != NSObject.self {
      defer { current = class_getSuperclass(owner) }
      guard RuntimeSafety.classIsSafe(owner) else { continue }
      for meta in RuntimeIvar.ivars(of: owner)
      where RuntimeSafety.ivarIsSafe(meta.name, on: owner) && matches(meta.name) {
        result.append(
          InspectedIvar(
            name: meta.name, type: meta.typeEncoding,
            value: readValue(of: object, owner: owner, ivar: meta, resolveNode: resolveNode)))
      }
    }
    return result
  }

  /// Read one ivar's value off the live object. Object ivars go through
  /// `object_getIvar` (ARC-safe); scalars are a memory read at the ivar offset
  /// interpreted by its `@encode` type; anything else is `null` (not decoded in v1).
  private static func readValue(
    of object: NSObject, owner: AnyClass, ivar: RuntimeIvar, resolveNode: (NSObject) -> String?
  ) -> JSONValue {
    guard let first = ivar.typeEncoding.first else { return .null }

    if first == "@" {
      guard let handle = class_getInstanceVariable(owner, ivar.name) else { return .null }
      return objectValue(object_getIvar(object, handle) as AnyObject?, resolveNode: resolveNode)
    }

    let base = Unmanaged.passUnretained(object).toOpaque()
    let offset = ivar.offset
    switch first {
    case "q", "l": return .number(Double(base.load(fromByteOffset: offset, as: Int.self)))
    case "Q", "L": return .number(Double(base.load(fromByteOffset: offset, as: UInt.self)))
    case "i": return .number(Double(base.load(fromByteOffset: offset, as: Int32.self)))
    case "I": return .number(Double(base.load(fromByteOffset: offset, as: UInt32.self)))
    case "s": return .number(Double(base.load(fromByteOffset: offset, as: Int16.self)))
    case "S": return .number(Double(base.load(fromByteOffset: offset, as: UInt16.self)))
    case "c": return .number(Double(base.load(fromByteOffset: offset, as: Int8.self)))
    case "C": return .number(Double(base.load(fromByteOffset: offset, as: UInt8.self)))
    case "B": return .bool(base.load(fromByteOffset: offset, as: Bool.self))
    case "f": return .number(Double(base.load(fromByteOffset: offset, as: Float.self)))
    case "d": return .number(base.load(fromByteOffset: offset, as: Double.self))
    default: return .null
    }
  }

  /// An object value, normalized to `{class}` (plus `node` when it is a registered
  /// view) — never a raw pointer, never an invoked `-description`.
  private static func objectValue(_ value: AnyObject?, resolveNode: (NSObject) -> String?)
    -> JSONValue
  {
    guard let value else { return .null }
    let className = NSStringFromClass(object_getClass(value) ?? type(of: value))
    var fields: [String: JSONValue] = ["class": .string(className)]
    if let object = value as? NSObject, let node = resolveNode(object) {
      fields["node"] = .string(node)
    }
    return .object(fields)
  }
}
