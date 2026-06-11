import ObjectiveC

// SPEC: domain.runtime.reflection
/// An eager, `Sendable` snapshot of everything a single Objective-C class
/// declares — the aggregator port of FLEX's `FLEXMirror`. Where the four unit
/// types (`RuntimeProperty`, `RuntimeIvar`, `RuntimeMethod`, `RuntimeProtocol`)
/// each reflect one *kind* of member, `RuntimeMirror` reflects one *class* and
/// composes all four into a single value. It walks one level only: the members a
/// class declares itself, never inherited ones — the superclass chain is exposed
/// lazily through `superMirror`, matching FLEX's "compute, don't cache" rule.
///
/// Following FLEX, reflecting an **instance** and reflecting its **class** yield
/// the same mirror: in both cases `properties` / `methods` are the *instance*
/// members and `classProperties` / `classMethods` are the *class* members. The
/// distinction the runtime draws is class-vs-metaclass, not object-vs-class, so
/// the subject is reduced to its class on the way in and the object itself is not
/// retained — every field is materialized into plain value types here, so the
/// snapshot can cross actor and IPC boundaries.
public struct RuntimeMirror: Sendable {
  /// The reflected class's name, from `class_getName`. For an instance subject,
  /// this is the name of `object_getClass(object)`.
  public let className: String

  /// The **instance** properties the class declares itself, via
  /// `RuntimeProperty.properties(of:)` over the class.
  public let properties: [RuntimeProperty]

  /// The **class** properties the class declares itself, via
  /// `RuntimeProperty.classProperties(of:)` over the metaclass.
  public let classProperties: [RuntimeProperty]

  /// The instance variables the class declares itself, via
  /// `RuntimeIvar.ivars(of:)`. (Ivars are an instance-only concept; there is no
  /// metaclass equivalent.)
  public let ivars: [RuntimeIvar]

  /// The **instance** methods the class declares itself, via
  /// `RuntimeMethod.methods(of:)` over the class.
  public let methods: [RuntimeMethod]

  /// The **class** methods the class declares itself, via
  /// `RuntimeMethod.classMethods(of:)` over the metaclass.
  public let classMethods: [RuntimeMethod]

  /// The protocols the class *directly* declares conformance to, via
  /// `RuntimeProtocol.conformances(of:)`. One level only — not the superclass's.
  public let protocols: [RuntimeProtocol]

  /// The reflected class itself, kept only to drive `superMirror`. Not a member
  /// of the snapshot's value identity; an `AnyClass` is a runtime-owned, immortal
  /// metadata pointer, which makes the struct safely `Sendable`.
  private let reflectedClass: AnyClass

  /// Reflect a live instance. The subject is reduced to its class with
  /// `object_getClass`; the instance is not retained.
  public init(reflecting object: AnyObject) {
    // `object_getClass` gives the real ISA (a KVO/private subclass, if any);
    // fall back to the static dynamic type rather than force-unwrap.
    self.init(reflectingClass: object_getClass(object) ?? type(of: object))
  }

  /// Reflect a class object. Composes the four unit reflectors over the class and
  /// its metaclass, materializing every member into value types.
  public init(reflectingClass cls: AnyClass) {
    self.reflectedClass = cls
    self.className = String(cString: class_getName(cls))
    self.properties = RuntimeProperty.properties(of: cls)
    self.classProperties = RuntimeProperty.classProperties(of: cls)
    self.ivars = RuntimeIvar.ivars(of: cls)
    self.methods = RuntimeMethod.methods(of: cls)
    self.classMethods = RuntimeMethod.classMethods(of: cls)
    self.protocols = RuntimeProtocol.conformances(of: cls)
  }

  /// A mirror of the reflected class's superclass, or `nil` at the root of the
  /// chain (a class with no superclass, e.g. `NSObject`). Computed on each access
  /// — never cached — so walking the chain costs only what is asked for. Mirrors
  /// FLEX's `superMirror`, which reflects `class_getSuperclass` of the subject.
  public var superMirror: RuntimeMirror? {
    guard let superclass = class_getSuperclass(reflectedClass) else {
      return nil
    }
    return RuntimeMirror(reflectingClass: superclass)
  }
}
