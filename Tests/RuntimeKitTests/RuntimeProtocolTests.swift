import Foundation
import TestSupport
import Testing

@testable import RuntimeKit

// A fixture protocol with one required and one optional instance method, plus a
// required property, refining NSObjectProtocol — reflected against the runtime in
// this process. `@objc` so the protocol is registered and `objc_getProtocol` can
// find it by name.
@objc(RKFixtureProtocol) private protocol RKFixtureProtocol: NSObjectProtocol {
  @objc func requiredGreeting() -> String
  @objc optional func optionalFarewell(to name: String) -> Int
  @objc var fixtureTag: String { get }
}

// A class that declares conformance to the fixture protocol and NSCopying, so
// `conformances(of:)` has known protocols to find.
@objc(RKConformingFixture) private class RKConformingFixture: NSObject, RKFixtureProtocol, NSCopying
{
  @objc var fixtureTag: String { "tag" }
  @objc func requiredGreeting() -> String { "hi" }
  func copy(with zone: NSZone? = nil) -> Any { self }
}

// SPEC: domain.runtime.reflection
@Suite(.spec("domain.runtime.reflection"))
struct RuntimeProtocolTests {

  @Test(.scenario("scenario.runtime.reflection.protocol-by-name"))
  func `init by name resolves a registered protocol and is nil for a bogus name`() throws {
    let copying = try #require(RuntimeProtocol(named: "NSCopying"))
    #expect(copying.name == "NSCopying")

    #expect(RuntimeProtocol(named: "RKDefinitelyNotARealProtocol") == nil)
  }

  @Test(.scenario("scenario.runtime.reflection.protocol-methods"))
  func `NSCopying lists copyWithZone as a required instance method`() throws {
    let copying = try #require(RuntimeProtocol(named: "NSCopying"))

    let selectors = copying.requiredInstanceMethods.map(\.selector)
    #expect(selectors.contains("copyWithZone:"), "got \(selectors)")

    let copyWithZone = try #require(
      copying.requiredInstanceMethods.first { $0.selector == "copyWithZone:" })
    // `id copyWithZone:(NSZone *)` — returns an object (`@`), takes self/_cmd/zone.
    #expect(copyWithZone.typeEncoding.first == "@", "got \(copyWithZone.typeEncoding)")
    #expect(copyWithZone.typeEncoding.contains("@"))
  }

  @Test(.scenario("scenario.runtime.reflection.protocol-methods"))
  func `a fixture protocol separates its required and optional methods`() throws {
    let proto = try #require(RuntimeProtocol(named: "RKFixtureProtocol"))

    let required = proto.requiredInstanceMethods.map(\.selector)
    let optional = proto.optionalInstanceMethods.map(\.selector)

    // The Swift→ObjC bridge folds the `to name:` external label into the
    // selector, so `optionalFarewell(to:)` reflects as `optionalFarewellTo:`.
    #expect(required.contains("requiredGreeting"), "required: \(required)")
    #expect(optional.contains("optionalFarewellTo:"), "optional: \(optional)")
    // The optional method must NOT appear in the required list and vice versa.
    #expect(!required.contains("optionalFarewellTo:"))
    #expect(!optional.contains("requiredGreeting"))
  }

  @Test(.scenario("scenario.runtime.reflection.protocol-methods"))
  func `a required property surfaces its getter in the required methods`() throws {
    let proto = try #require(RuntimeProtocol(named: "RKFixtureProtocol"))
    // FLEX's contract: property accessors appear in the method descriptions.
    let required = proto.requiredInstanceMethods.map(\.selector)
    #expect(required.contains("fixtureTag"), "got \(required)")
    // And the property name itself is reflected.
    #expect(proto.propertyNames.contains("fixtureTag"), "got \(proto.propertyNames)")
  }

  @Test(.scenario("scenario.runtime.reflection.protocol-conformed"))
  func `a refining protocol lists its parent in conformedProtocols`() throws {
    let proto = try #require(RuntimeProtocol(named: "RKFixtureProtocol"))
    // RKFixtureProtocol refines NSObject (NSObjectProtocol).
    #expect(proto.conformedProtocols.contains("NSObject"), "got \(proto.conformedProtocols)")
  }

  @Test(.scenario("scenario.runtime.reflection.protocol-conformances"))
  func `conformances of a class returns the protocols it declares`() throws {
    let names = RuntimeProtocol.conformances(of: RKConformingFixture.self).map(\.name)
    #expect(names.contains("RKFixtureProtocol"), "got \(names)")
    #expect(names.contains("NSCopying"), "got \(names)")
  }

  @Test
  func `conformances reflects only what the class itself declares`() {
    // NSObject's own protocol list includes the NSObject protocol (and whatever
    // loaded frameworks attach), but never our fixture protocol — a class only
    // surfaces its own declared conformances, not those of unrelated classes.
    let names = RuntimeProtocol.conformances(of: NSObject.self).map(\.name)
    #expect(!names.contains("RKFixtureProtocol"), "got \(names)")
  }

  @Test(.scenario("scenario.runtime.reflection.method-description"))
  func `a method description carries the demangled selector and a type encoding`() throws {
    let proto = try #require(RuntimeProtocol(named: "NSCopying"))
    let desc = try #require(proto.requiredInstanceMethods.first)
    #expect(!desc.selector.isEmpty)
    #expect(!desc.typeEncoding.isEmpty)
  }

  @Test
  func `MethodDescription is equatable by its parts`() {
    let a = MethodDescription(selector: "foo:", typeEncoding: "v16@0:8")
    let b = MethodDescription(selector: "foo:", typeEncoding: "v16@0:8")
    let c = MethodDescription(selector: "bar", typeEncoding: "v16@0:8")
    #expect(a == b)
    #expect(a != c)
  }

  @Test
  func `snapshot fields are read eagerly and survive the protocol handle`() throws {
    // Constructing from a Protocol* must not retain it: every field is plain data.
    let proto = try #require(RuntimeProtocol(named: "NSCopying"))
    let copy = proto
    #expect(copy == proto)
    #expect(copy.name == "NSCopying")
  }
}
