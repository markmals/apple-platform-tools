import ObjectiveC

// SPEC: domain.runtime.reflection
/// The metadata of one Objective-C method — a port of the reflection half of
/// FLEX's `FLEXMethod`. Reading a method's *shape*: its selector name, full type
/// encoding, and argument count. The invocation machinery of `FLEXMethod`
/// (`sendMessage:`, `NSInvocation`/`va_list` dispatch, `implementation` get/set,
/// `swapImplementations:`, the `NSMethodSignature`-derived return type/size) is
/// out of headless scope and is deliberately not ported.
public struct RuntimeMethod: Sendable {
  /// The selector name, e.g. `initWithFrame:`. From `sel_getName(method_getName(...))`.
  public let selectorName: String
  /// The full method type encoding the runtime stores — return type followed by
  /// the argument frame with offsets, e.g. `v16@0:8`. From `method_getTypeEncoding`;
  /// `""` when the runtime has no encoding. Not run through `TypeEncodingParser`:
  /// cleaning is only needed to feed `NSMethodSignature`, which metadata never does.
  public let typeEncoding: String
  /// The runtime's argument count, which always includes the two implicit
  /// arguments `self` and `_cmd`; a zero-argument selector reports `2`. From
  /// `method_getNumberOfArguments`, carried verbatim.
  public let argumentCount: Int

  /// Build the metadata for a single `Method` handle. The handle does not escape:
  /// every field is materialized into this value type here.
  init(_ method: Method) {
    self.selectorName = String(cString: sel_getName(method_getName(method)))
    self.typeEncoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? ""
    self.argumentCount = Int(method_getNumberOfArguments(method))
  }

  /// Every **instance** method the class itself declares (not inherited), in
  /// runtime order. Mirrors a `class_copyMethodList` walk.
  public static func methods(of cls: AnyClass) -> [RuntimeMethod] {
    methods(listingMethodsOf: cls)
  }

  /// Every **class** method the class itself declares, reflected off its
  /// metaclass. Returns `[]` when the metaclass is unavailable.
  public static func classMethods(of cls: AnyClass) -> [RuntimeMethod] {
    guard let metaclass = object_getClass(cls) else { return [] }
    return methods(listingMethodsOf: metaclass)
  }

  /// The shared `class_copyMethodList` walk behind both enumerators.
  private static func methods(listingMethodsOf cls: AnyClass) -> [RuntimeMethod] {
    var count: UInt32 = 0
    guard let list = class_copyMethodList(cls, &count) else { return [] }
    defer { free(list) }
    let buffer = UnsafeBufferPointer(start: list, count: Int(count))
    return buffer.map(RuntimeMethod.init)
  }
}
