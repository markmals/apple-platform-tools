import Foundation
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.reflection
//
// Two oracles. For *reflection* (the live-runtime walk), an in-process `@objc`
// fixture class — reflecting a class loaded into the test process is
// deterministic and runs on any Mac, no injection. For *attribute parsing*, the
// canonical `property_getAttributes` strings parsed directly: Swift's `@objc`
// emitter cannot produce every attribute (it never emits `copy`, `readonly` on a
// stored var, or `getter=`/`setter=`), so the storage/readonly/accessor cases
// are pinned against the string forms the ObjC runtime emits for hand-written
// properties — which is exactly what the parser must handle in the field.

/// A fixture for the live-runtime reflection walk. The emitted attribute strings
/// (verified against the runtime) are:
///   title      -> T@"NSString",N,&,Vtitle
///   count      -> Tq,N,Vcount
///   delegate   -> T@"NSObject",N,W,Vdelegate
///   shared     -> T@"NSString",N,R   (class property)
@objc(RKPropertyFixture)
private class RKPropertyFixture: NSObject {
  /// Strong object property — `T@"NSString",N,&,Vtitle`.
  @objc var title: NSString = ""
  /// Scalar — `Tq,N,Vcount`.
  @objc var count: Int = 0
  /// `weak` object — `T@"NSObject",N,W,Vdelegate`.
  @objc weak var delegate: NSObject?
  /// A declared **class** property — surfaced only by `classProperties(of:)`,
  /// and (being a computed get-only class var) read-only: `T@"NSString",N,R`.
  @objc class var shared: NSString { "" }
}

/// A subclass declaring its own property, to prove declared-only reflection.
@objc(RKPropertySubFixture)
private class RKPropertySubFixture: RKPropertyFixture {
  @objc var extra: Int = 0
}

@Suite(.spec("domain.runtime.reflection"))
struct RuntimePropertyTests {

  private static func property(
    named name: String, in properties: [RuntimeProperty]
  ) -> RuntimeProperty? {
    properties.first { $0.name == name }
  }

  // MARK: - Live-runtime reflection

  @Test(.scenario("scenario.runtime.reflection.declared-property"))
  func `reflecting a fixture finds a declared property by name with its type encoding`() throws {
    let properties = RuntimeProperty.properties(of: RKPropertyFixture.self)
    let title = try #require(Self.property(named: "title", in: properties))
    #expect(title.typeEncoding == "@\"NSString\"")
    // typeEncoding is a convenience mirror of the parsed attribute.
    #expect(title.typeEncoding == title.attributes.typeEncoding)
  }

  @Test(.scenario("scenario.runtime.reflection.storage-attributes"))
  func `strong weak and nonatomic storage reflect from the runtime attribute string`() throws {
    let properties = RuntimeProperty.properties(of: RKPropertyFixture.self)
    let title = try #require(Self.property(named: "title", in: properties))
    let delegate = try #require(Self.property(named: "delegate", in: properties))
    #expect(title.attributes.isRetained)
    #expect(delegate.attributes.isWeak)
    // `@objc` properties are nonatomic — the `N` flag is present.
    #expect(title.attributes.isNonatomic)
    #expect(delegate.attributes.isNonatomic)
  }

  @Test(.scenario("scenario.runtime.reflection.backing-ivar"))
  func `a property's backing ivar reflects from the V component`() throws {
    let properties = RuntimeProperty.properties(of: RKPropertyFixture.self)
    let title = try #require(Self.property(named: "title", in: properties))
    // Swift names the synthesized ivar after the property (no leading underscore).
    #expect(title.attributes.backingIvar == "title")
  }

  @Test(.scenario("scenario.runtime.reflection.class-property"))
  func `classProperties finds a class property the instance reflector does not`() throws {
    let instanceProps = RuntimeProperty.properties(of: RKPropertyFixture.self)
    let classProps = RuntimeProperty.classProperties(of: RKPropertyFixture.self)
    #expect(Self.property(named: "shared", in: instanceProps) == nil)
    let shared = try #require(Self.property(named: "shared", in: classProps))
    #expect(shared.typeEncoding == "@\"NSString\"")
  }

  @Test(.scenario("scenario.runtime.reflection.readonly-attribute"))
  func `a readonly reflected property parses to isReadOnly and a readwrite one to false`() throws {
    // `shared` is a get-only class var: the runtime emits `R`.
    let classProps = RuntimeProperty.classProperties(of: RKPropertyFixture.self)
    let shared = try #require(Self.property(named: "shared", in: classProps))
    #expect(shared.attributes.isReadOnly)
    // A stored var is readwrite: no `R`.
    let instanceProps = RuntimeProperty.properties(of: RKPropertyFixture.self)
    let title = try #require(Self.property(named: "title", in: instanceProps))
    #expect(!title.attributes.isReadOnly)
  }

  @Test(.scenario("scenario.runtime.reflection.declared-only"))
  func `a property reflector returns only the class's own properties`() throws {
    let subProps = RuntimeProperty.properties(of: RKPropertySubFixture.self)
    // The subclass declares `extra`; it must NOT surface the superclass's `title`.
    #expect(Self.property(named: "extra", in: subProps) != nil)
    #expect(Self.property(named: "title", in: subProps) == nil)
  }

  // MARK: - PropertyAttributes parser (canonical runtime strings)

  @Test(.scenario("scenario.runtime.reflection.declared-property"))
  func `a strong object property string parses type encoding and retain`() {
    // The exact string the runtime emits for `@objc var title: NSString`.
    let attrs = PropertyAttributes(parsing: "T@\"NSString\",N,&,Vtitle")
    #expect(attrs.typeEncoding == "@\"NSString\"")
    #expect(attrs.isRetained)
    #expect(attrs.isNonatomic)
    #expect(attrs.backingIvar == "title")
    #expect(!attrs.isReadOnly)
    #expect(!attrs.isCopy)
    #expect(!attrs.isWeak)
  }

  @Test(.scenario("scenario.runtime.reflection.readonly-attribute"))
  func `a readonly property string parses isReadOnly`() {
    // Canonical hand-written readonly object property.
    let readonly = PropertyAttributes(parsing: "T@\"NSString\",R,C")
    #expect(readonly.isReadOnly)
    #expect(readonly.isCopy)
    let readwrite = PropertyAttributes(parsing: "T@\"NSString\",&,Vthing")
    #expect(!readwrite.isReadOnly)
  }

  @Test(.scenario("scenario.runtime.reflection.storage-attributes"))
  func `copy and weak storage strings parse to isCopy and isWeak`() {
    let copy = PropertyAttributes(parsing: "T@\"NSString\",C,N,V_name")
    #expect(copy.isCopy)
    #expect(!copy.isRetained)
    let weak = PropertyAttributes(parsing: "T@\"NSObject\",W,N,V_obj")
    #expect(weak.isWeak)
  }

  @Test(.scenario("scenario.runtime.reflection.backing-ivar"))
  func `the V component parses to the backing ivar name`() {
    let attrs = PropertyAttributes(parsing: "Tq,N,V_count")
    #expect(attrs.backingIvar == "_count")
  }

  @Test(.scenario("scenario.runtime.reflection.custom-accessors"))
  func `custom getter and setter strings parse from G and S`() {
    // Canonical string for `@property (getter=isOn, setter=setOn:) BOOL on;`.
    let attrs = PropertyAttributes(parsing: "TB,N,GisOn,SsetOn:,V_on")
    #expect(attrs.customGetter == "isOn")
    #expect(attrs.customSetter == "setOn:")
    #expect(attrs.backingIvar == "_on")
  }

  @Test
  func `the retain and dynamic flags parse from & and D`() {
    let attrs = PropertyAttributes(parsing: "T@,&,D")
    #expect(attrs.isRetained)
    #expect(attrs.isDynamic)
  }

  @Test
  func `the old-style type encoding and GC flag parse from lowercase t and P`() {
    let attrs = PropertyAttributes(parsing: "T@\"NSString\",t@,P,V_x")
    #expect(attrs.oldTypeEncoding == "@")
    #expect(attrs.isGarbageCollected)
  }

  // MARK: - PropertyAttributes parser (degenerate input)

  @Test(.scenario("scenario.runtime.reflection.empty-attributes"))
  func `parsing degenerate attribute strings does not crash`() {
    let empty = PropertyAttributes(parsing: "")
    #expect(empty.typeEncoding == nil)
    #expect(!empty.isReadOnly)
    #expect(!empty.isCopy)

    // A lone flag char and an unknown char are tolerated.
    let loneFlag = PropertyAttributes(parsing: "R")
    #expect(loneFlag.isReadOnly)

    let unknown = PropertyAttributes(parsing: "Zfoo,R")
    #expect(unknown.isReadOnly)
    #expect(unknown.typeEncoding == nil)
  }

  @Test
  func `a lone value key with no trailing value yields an empty string`() {
    // `V` with nothing after it: empty backing-ivar name, not nil.
    let attrs = PropertyAttributes(parsing: "T@,V")
    #expect(attrs.typeEncoding == "@")
    #expect(attrs.backingIvar == "")
  }
}
