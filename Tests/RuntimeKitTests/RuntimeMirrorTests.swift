import Foundation
import ObjectiveC
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.reflection
//
// The aggregator oracle: a two-level `@objc` fixture reflected in the test
// process (no injection). `RKMirrorBase` declares known instance/class members
// and conforms to a protocol; `RKMirrorFixture` subclasses it and adds its own.
// The assertions pin (1) that `RuntimeMirror` composes the four unit reflectors
// into the right buckets, (2) that it reflects only the class's *own* members
// (the superclass's live behind `superMirror`), and (3) that the `superMirror`
// chain walks Fixture -> Base -> NSObject -> nil.

@objc(RKMirrorPing)
private protocol RKMirrorPing {
  func ping()
}

@objc(RKMirrorBase)
private class RKMirrorBase: NSObject, RKMirrorPing {
  @objc var baseLabel: NSString = ""
  @objc func ping() {}
  @objc class func baseGreeting() -> NSString { "hi" }
}

@objc(RKMirrorFixture)
private class RKMirrorFixture: RKMirrorBase {
  @objc var count: Int = 0
  @objc var ratio: Double = 0

  @objc func noArgs() {}
  @objc func takesOne(_ value: Int) {}
  @objc class func fixtureGreeting() -> NSString { "hello" }
}

// SPEC: domain.runtime.reflection
@Suite(.spec("domain.runtime.reflection"))
struct RuntimeMirrorTests {

  @Test
  func `reflecting a class names it and aggregates its declared instance members`() {
    let mirror = RuntimeMirror(reflectingClass: RKMirrorFixture.self)
    #expect(mirror.className == "RKMirrorFixture")

    let ivarNames = Set(mirror.ivars.map(\.name))
    #expect(ivarNames.isSuperset(of: ["count", "ratio"]))

    let propertyNames = Set(mirror.properties.map(\.name))
    #expect(propertyNames.isSuperset(of: ["count", "ratio"]))

    let selectors = Set(mirror.methods.map(\.selectorName))
    #expect(selectors.isSuperset(of: ["noArgs", "takesOne:"]))
  }

  @Test
  func `class methods and class properties land in their own buckets`() {
    let mirror = RuntimeMirror(reflectingClass: RKMirrorFixture.self)

    let classSelectors = Set(mirror.classMethods.map(\.selectorName))
    #expect(classSelectors.contains("fixtureGreeting"))
    // The instance method must not leak into the class-method bucket.
    #expect(!classSelectors.contains("noArgs"))
    // ...and the class method must not leak into the instance bucket.
    #expect(!Set(mirror.methods.map(\.selectorName)).contains("fixtureGreeting"))
  }

  @Test
  func `the mirror aggregates the same units the standalone reflectors return`() {
    let mirror = RuntimeMirror(reflectingClass: RKMirrorFixture.self)
    // The aggregator must be a pure composition of the unit reflectors, not a
    // re-implementation — same elements, same order.
    #expect(mirror.ivars.map(\.name) == RuntimeIvar.ivars(of: RKMirrorFixture.self).map(\.name))
    #expect(
      mirror.methods.map(\.selectorName)
        == RuntimeMethod.methods(of: RKMirrorFixture.self).map(\.selectorName))
    #expect(
      mirror.classMethods.map(\.selectorName)
        == RuntimeMethod.classMethods(of: RKMirrorFixture.self).map(\.selectorName))
    #expect(
      mirror.properties.map(\.name)
        == RuntimeProperty.properties(of: RKMirrorFixture.self).map(\.name))
  }

  @Test
  func `the mirror reflects only the class's own members, not inherited ones`() {
    let mirror = RuntimeMirror(reflectingClass: RKMirrorFixture.self)
    // `baseLabel` / `ping` / `baseGreeting` are declared on the superclass.
    #expect(!Set(mirror.ivars.map(\.name)).contains("baseLabel"))
    #expect(!Set(mirror.methods.map(\.selectorName)).contains("ping"))
    #expect(!Set(mirror.classMethods.map(\.selectorName)).contains("baseGreeting"))
  }

  @Test
  func `protocols reflects the class's own direct conformances`() {
    // The base declares the conformance; the subclass does not redeclare it.
    let base = RuntimeMirror(reflectingClass: RKMirrorBase.self)
    #expect(Set(base.protocols.map(\.name)).contains("RKMirrorPing"))
  }

  @Test
  func `superMirror walks one level to the superclass and reflects its members`() throws {
    let mirror = RuntimeMirror(reflectingClass: RKMirrorFixture.self)
    let superMirror = try #require(mirror.superMirror)
    #expect(superMirror.className == "RKMirrorBase")
    // The superclass's own members the leaf mirror omitted now appear here.
    #expect(Set(superMirror.ivars.map(\.name)).contains("baseLabel"))
    #expect(Set(superMirror.methods.map(\.selectorName)).contains("ping"))
  }

  @Test
  func `the superMirror chain reaches NSObject and terminates at nil`() throws {
    var mirror: RuntimeMirror? = RuntimeMirror(reflectingClass: RKMirrorFixture.self)
    var names: [String] = []
    while let current = mirror {
      names.append(current.className)
      mirror = current.superMirror
    }
    // Fixture -> Base -> NSObject, then nil. NSObject is the root: its superMirror
    // is nil, so the walk terminates.
    #expect(names == ["RKMirrorFixture", "RKMirrorBase", "NSObject"])
  }

  @Test
  func `reflecting an instance yields the same class-level snapshot as reflecting its class`() {
    // FLEX's invariant: reflecting an instance reflects its class. `properties`
    // are the instance members in both cases.
    let viaInstance = RuntimeMirror(reflecting: RKMirrorFixture())
    let viaClass = RuntimeMirror(reflectingClass: RKMirrorFixture.self)
    #expect(viaInstance.className == viaClass.className)
    #expect(viaInstance.methods.map(\.selectorName) == viaClass.methods.map(\.selectorName))
    #expect(
      viaInstance.classMethods.map(\.selectorName) == viaClass.classMethods.map(\.selectorName))
  }
}
