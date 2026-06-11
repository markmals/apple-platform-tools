import ObjectiveC

// SPEC: domain.runtime.reflection
/// The metadata of one Objective-C `@property` — a port of the reflection half
/// of FLEX's `FLEXProperty`. Reading a property's *shape*: its name, type
/// encoding, and parsed attributes. The value get/set machinery of `FLEXProperty`
/// (`getValue:`, the block-as-IMP `getterWithImplementation:` / `setterWithImplementation:`,
/// boxing, image/bundle attribution) is out of headless scope and is deliberately
/// not ported.
public struct RuntimeProperty: Sendable {
  /// The property's name, e.g. `title`. From `property_getName`.
  public let name: String
  /// The property's type encoding, e.g. `@"NSString"`, `q`, `{CGRect=…}`. A
  /// convenience mirror of `attributes.typeEncoding ?? ""`; `""` when the runtime
  /// emits no `T` attribute. (FLEX FB7499230 caveat: the runtime's `T` encoding
  /// is not always correct.)
  public let typeEncoding: String
  /// The property's parsed attribute string (storage, atomicity, backing ivar,
  /// custom accessors). From `property_getAttributes`.
  public let attributes: PropertyAttributes

  /// Build the metadata for a single `objc_property_t` handle. The handle does
  /// not escape: every field is materialized into this value type here.
  init(_ property: objc_property_t) {
    self.name = String(cString: property_getName(property))
    let raw = property_getAttributes(property).map { String(cString: $0) } ?? ""
    self.attributes = PropertyAttributes(parsing: raw)
    self.typeEncoding = attributes.typeEncoding ?? ""
  }

  /// Every **instance** property the class itself declares (not inherited), in
  /// runtime-declaration order. Mirrors a `class_copyPropertyList` walk.
  public static func properties(of cls: AnyClass) -> [RuntimeProperty] {
    properties(listingPropertiesOf: cls)
  }

  /// Every **class** property the class itself declares, reflected off its
  /// metaclass. Returns `[]` when the metaclass is unavailable.
  public static func classProperties(of cls: AnyClass) -> [RuntimeProperty] {
    guard let metaclass = objc_getMetaClass(class_getName(cls)) as? AnyClass else { return [] }
    return properties(listingPropertiesOf: metaclass)
  }

  /// The shared `class_copyPropertyList` walk behind both enumerators.
  private static func properties(listingPropertiesOf cls: AnyClass) -> [RuntimeProperty] {
    var count: UInt32 = 0
    guard let list = class_copyPropertyList(cls, &count) else { return [] }
    defer { free(list) }
    let buffer = UnsafeBufferPointer(start: list, count: Int(count))
    return buffer.map(RuntimeProperty.init)
  }
}

// SPEC: domain.runtime.reflection
/// The parsed Objective-C property-attribute string — a port of
/// `FLEXPropertyAttributes` plus `NSString+ObjcRuntime`'s `propertyAttributes`.
/// `property_getAttributes` returns a comma-separated string such as
/// `T@"NSString",C,N,V_title`; each component is keyed by its first character.
/// FLEX's mutable subclass and the `class_replaceProperty` list-rebuilding are
/// out of headless scope and are not ported.
public struct PropertyAttributes: Sendable {
  /// The `T` component — the property's type encoding. `nil` when absent.
  public let typeEncoding: String?
  /// The `V` component — the name of the backing instance variable. `nil` when
  /// absent (always absent for `@dynamic` and class properties).
  public let backingIvar: String?
  /// The `t` component — the old-style type encoding. `nil` when absent.
  public let oldTypeEncoding: String?
  /// The `G` component — a custom getter selector name. `nil` when the property
  /// uses the default getter.
  public let customGetter: String?
  /// The `S` component — a custom setter selector name. `nil` when the property
  /// uses the default setter.
  public let customSetter: String?
  /// The `R` flag — `readonly`.
  public let isReadOnly: Bool
  /// The `C` flag — `copy` storage.
  public let isCopy: Bool
  /// The `&` flag — `retain` / `strong` storage.
  public let isRetained: Bool
  /// The `N` flag — `nonatomic`.
  public let isNonatomic: Bool
  /// The `D` flag — `@dynamic`.
  public let isDynamic: Bool
  /// The `W` flag — `weak` storage.
  public let isWeak: Bool
  /// The `P` flag — GC-eligible. Legacy; never set on modern targets.
  public let isGarbageCollected: Bool

  /// Parse a `property_getAttributes` string. Total: an empty string yields an
  /// all-default value, flags default to `false` when absent, value fields to
  /// `nil`, and unknown component chars are ignored (FLEX's `switch` has no
  /// `default`). A lone key char with no trailing value yields an empty-string
  /// value, matching FLEX's `stringByDeletingCharacterAtIndex:0`.
  public init(parsing string: String) {
    var typeEncoding: String?
    var backingIvar: String?
    var oldTypeEncoding: String?
    var customGetter: String?
    var customSetter: String?
    var isReadOnly = false
    var isCopy = false
    var isRetained = false
    var isNonatomic = false
    var isDynamic = false
    var isWeak = false
    var isGarbageCollected = false

    if !string.isEmpty {
      for component in string.split(separator: ",", omittingEmptySubsequences: false) {
        guard let key = component.first else { continue }
        let value = String(component.dropFirst())
        switch key {
        case "T": typeEncoding = value
        case "V": backingIvar = value
        case "t": oldTypeEncoding = value
        case "G": customGetter = value
        case "S": customSetter = value
        case "R": isReadOnly = true
        case "C": isCopy = true
        case "&": isRetained = true
        case "N": isNonatomic = true
        case "D": isDynamic = true
        case "W": isWeak = true
        case "P": isGarbageCollected = true
        default: break
        }
      }
    }

    self.typeEncoding = typeEncoding
    self.backingIvar = backingIvar
    self.oldTypeEncoding = oldTypeEncoding
    self.customGetter = customGetter
    self.customSetter = customSetter
    self.isReadOnly = isReadOnly
    self.isCopy = isCopy
    self.isRetained = isRetained
    self.isNonatomic = isNonatomic
    self.isDynamic = isDynamic
    self.isWeak = isWeak
    self.isGarbageCollected = isGarbageCollected
  }
}
