import Foundation
import ObjectiveC
import RuntimeKit
import UIToolCore

// SPEC: command.uitool.classes
/// Browse the **target's** loaded classes from inside it: list the names matching a
/// pattern (`objc_copyClassList`), or reflect one class's declared shape via
/// [[domain.runtime.reflection]]. Metadata only — no instance, no values, no target
/// code run. **Runs off the main thread**: class metadata is thread-safe to read,
/// and a 30k-class enumeration would blow the bounded main-thread hop.
enum ClassBrowser {

  /// The loaded class names matching `matches`, sorted and capped at `limit`. Uses
  /// the two-call `objc_getClassList` pattern with our own buffer (no copyClassList
  /// free to get wrong), and `class_getName` (a safe C-string read — never sends a
  /// message to a class that may not accept one).
  static func list(pattern: String, matches: (String) -> Bool, limit: Int) -> ClassList {
    let classCount = objc_getClassList(nil, 0)
    guard classCount > 0 else {
      return ClassList(match: pattern, count: 0, truncated: false, names: [])
    }

    let buffer = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(classCount))
    defer { buffer.deallocate() }
    let filled = Int(objc_getClassList(AutoreleasingUnsafeMutablePointer(buffer), classCount))

    var names: [String] = []
    for index in 0..<filled {
      let name = String(cString: class_getName(buffer[index]))
      if matches(name) { names.append(name) }
    }
    names.sort()
    let total = names.count
    let truncated = total > limit
    return ClassList(
      match: pattern, count: total, truncated: truncated,
      names: truncated ? Array(names.prefix(limit)) : names)
  }

  /// Reflect one class by name: its superclass chain, declared ivars, properties,
  /// methods, and protocols. An unloaded name is `loaded: false`; an unsafe class is
  /// `loaded: true` with empty members (reflected for existence, not introspected).
  static func reflect(className: String) -> ClassInfo {
    guard let cls = NSClassFromString(className) else {
      return empty(className: className, loaded: false)
    }
    guard RuntimeSafety.classIsSafe(cls) else {
      return empty(className: className, loaded: true)
    }
    let mirror = RuntimeMirror(reflectingClass: cls)
    var superclasses: [String] = []
    var superMirror = mirror.superMirror
    while let current = superMirror {
      superclasses.append(current.className)
      superMirror = current.superMirror
    }
    return ClassInfo(
      class: mirror.className,
      loaded: true,
      superclasses: superclasses,
      ivars: mirror.ivars.map { ClassIvar(name: $0.name, type: $0.typeEncoding) },
      properties: mirror.properties.map(\.name).sorted(),
      methods: mirror.methods.map(\.selectorName).sorted(),
      classMethods: mirror.classMethods.map(\.selectorName).sorted(),
      protocols: mirror.protocols.map(\.name).sorted())
  }

  private static func empty(className: String, loaded: Bool) -> ClassInfo {
    ClassInfo(
      class: className, loaded: loaded, superclasses: [], ivars: [], properties: [], methods: [],
      classMethods: [], protocols: [])
  }
}
