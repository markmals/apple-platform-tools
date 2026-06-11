import Foundation
import ObjectiveC

// SPEC: domain.runtime.reflection
/// The runtime-safety denylist — a faithful port of FLEX's `FLEXRuntimeSafety`.
///
/// A handful of Objective-C classes and ivars are unsafe to introspect: sending
/// `+class`, reading an ivar, or building an `NSMethodSignature` over one of
/// their members crashes, hangs, or corrupts process state. FLEX hard-codes a
/// small denylist and consults it before any deeper introspection
/// (`FLEXClassIsSafe`, `FLEXIvarIsSafe`). `RuntimeSafety` carries the same
/// entries.
///
/// FLEX builds its sets in an `__attribute__((constructor))` that runs at load.
/// This port drops the constructor: the denylists are lazy `static let`s, so
/// there is no load-time work and no global mutable runtime state.
public enum RuntimeSafety {
  /// Class names FLEX refuses to introspect. Carried verbatim from
  /// `FLEXKnownUnsafeClassList` (19 entries). Matched by `NSStringFromClass`.
  public static let knownUnsafeClassNames: Set<String> = [
    "__ARCLite__",
    "__NSCFCalendar",
    "__NSCFTimer",
    "NSCFTimer",
    "__NSGenericDeallocHandler",
    "NSAutoreleasePool",
    "NSPlaceholderNumber",
    "NSPlaceholderString",
    "NSPlaceholderValue",
    "Object",
    "VMUArchitecture",
    "JSExport",
    "__NSAtom",
    "_NSZombie_",
    "_CNZombie_",
    "__NSMessage",
    "__NSMessageBuilder",
    "FigIrisAutoTrimmerMotionSampleExport",
    // `setVectors:` has an invalid type encoding that crashes NSMethodSignature.
    // `TypeEncodingParser` now defuses that hazard, but the entry is kept for
    // fidelity with FLEX.
    "_UIPointVector",
  ]

  /// `(className, ivarName)` pairs FLEX refuses to read. FLEX keys these on the
  /// `Ivar` pointer identity of `NSURL`'s `_urlString` / `_baseURL`; under
  /// non-injected reflection the `(class, name)` pair selects exactly the same
  /// ivars.
  static let knownUnsafeIvars: Set<UnsafeIvar> = [
    UnsafeIvar(className: "NSURL", ivarName: "_urlString"),
    UnsafeIvar(className: "NSURL", ivarName: "_baseURL"),
  ]

  /// Whether `cls` is safe to introspect.
  ///
  /// Rejects any class on the denylist (matched by name). Then applies FLEX's
  /// root-class rule: a class with no superclass is safe only if it is exactly
  /// `NSObject` or `NSProxy`. Every other class is treated as safe.
  public static func classIsSafe(_ cls: AnyClass) -> Bool {
    if knownUnsafeClassNames.contains(NSStringFromClass(cls)) {
      return false
    }

    // A root class (no superclass) is only safe if it is a known root.
    if class_getSuperclass(cls) == nil {
      return cls == NSObject.self || cls == NSProxy.self
    }

    return true
  }

  /// Whether the ivar named `name` on `cls` is safe to read.
  ///
  /// Rejects the known-unsafe ivars (`NSURL._urlString`, `NSURL._baseURL`),
  /// matching FLEX's pointer-identity check by name and walking up the
  /// superclass chain so a subclass of an owning class inherits the rejection.
  public static func ivarIsSafe(_ name: String, on cls: AnyClass) -> Bool {
    var current: AnyClass? = cls
    while let candidate = current {
      if knownUnsafeIvars.contains(
        UnsafeIvar(className: NSStringFromClass(candidate), ivarName: name))
      {
        return false
      }
      current = class_getSuperclass(candidate)
    }
    return true
  }
}

// SPEC: domain.runtime.reflection
/// One `(className, ivarName)` entry in the ivar denylist. A value type so the
/// denylist can be a plain `Set` resolved by name rather than by live `Ivar`
/// pointer identity (FLEX's approach), which would require the runtime at
/// denylist-construction time.
struct UnsafeIvar: Hashable {
  let className: String
  let ivarName: String
}
