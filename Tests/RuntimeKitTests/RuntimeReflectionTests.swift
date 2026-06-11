import Foundation
import ObjectiveC
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.reflection
/// A fixture with members of known shape, reflected in the test process itself
/// (no injection). The declared `@objc` ivars, instance methods, and class
/// method give the oracle exact names, encodings, and counts to assert against.
@objc(RKFixture)
private class RKFixture: NSObject {
  @objc var count: Int = 0
  @objc var label: NSString = ""
  @objc var ratio: Double = 0

  @objc func noArgs() {}
  @objc func takesOne(_ value: Int) {}
  @objc func takesTwo(_ first: Int, second: NSString) {}
  @objc class func classGreeting() -> NSString { "hi" }
}

// SPEC: domain.runtime.reflection
@Suite(.spec("domain.runtime.reflection"))
struct RuntimeReflectionTests {

  // MARK: - RuntimeIvar

  @Test
  func `ivars finds every declared ivar by name`() {
    let names = Set(RuntimeIvar.ivars(of: RKFixture.self).map(\.name))
    // Swift backs an `@objc var foo` with an ivar named `foo` (no underscore).
    #expect(names.isSuperset(of: ["count", "label", "ratio"]))
  }

  @Test
  func `an ivar carries its type encoding and parser-derived size`() throws {
    let ivars = RuntimeIvar.ivars(of: RKFixture.self)
    let count = try #require(ivars.first { $0.name == "count" })
    // A Swift `Int` ivar encodes as `q` (long long), 8 bytes.
    #expect(count.typeEncoding == "q")
    #expect(count.size == MemoryLayout<Int>.size)

    let ratio = try #require(ivars.first { $0.name == "ratio" })
    #expect(ratio.typeEncoding == "d")
    #expect(ratio.size == MemoryLayout<Double>.size)
  }

  @Test
  func `an object-typed ivar sizes to one pointer`() throws {
    let label = try #require(RuntimeIvar.ivars(of: RKFixture.self).first { $0.name == "label" })
    // Object encodings start with `@`; whether bare or quoted, they are one word.
    #expect(label.typeEncoding.hasPrefix("@"))
    #expect(label.size == MemoryLayout<UnsafeRawPointer>.size)
  }

  @Test
  func `ivar offsets are non-negative and strictly increasing in declaration order`() {
    let ivars = RuntimeIvar.ivars(of: RKFixture.self)
    #expect(ivars.allSatisfy { $0.offset >= 0 })
    let offsets = ivars.map(\.offset)
    #expect(offsets == offsets.sorted())
    #expect(Set(offsets).count == offsets.count, "offsets should be distinct")
  }

  @Test
  func `ivars only returns the class's own ivars, not inherited ones`() {
    // NSObject's `isa` lives on NSObject, not the fixture — it must not appear.
    let names = Set(RuntimeIvar.ivars(of: RKFixture.self).map(\.name))
    #expect(!names.contains("isa"))
  }

  @Test
  func `a class with no declared ivars reflects to an empty list`() {
    // NSObject itself declares exactly `isa`; a leaf class that adds nothing
    // would be empty — use a runtime-built empty class to pin the empty case.
    let empty: AnyClass = objc_allocateClassPair(NSObject.self, "RKEmptyFixture", 0)!
    objc_registerClassPair(empty)
    #expect(RuntimeIvar.ivars(of: empty).isEmpty)
  }

  // MARK: - RuntimeMethod

  @Test
  func `methods finds every declared instance method by selector`() {
    let selectors = Set(RuntimeMethod.methods(of: RKFixture.self).map(\.selectorName))
    #expect(selectors.isSuperset(of: ["noArgs", "takesOne:", "takesTwo:second:"]))
  }

  @Test
  func `argument count includes the two implicit self and _cmd arguments`() throws {
    let methods = RuntimeMethod.methods(of: RKFixture.self)
    let noArgs = try #require(methods.first { $0.selectorName == "noArgs" })
    #expect(noArgs.argumentCount == 2)

    let one = try #require(methods.first { $0.selectorName == "takesOne:" })
    #expect(one.argumentCount == 3)

    let two = try #require(methods.first { $0.selectorName == "takesTwo:second:" })
    #expect(two.argumentCount == 4)
  }

  @Test
  func `a method carries its full type encoding with the argument frame`() throws {
    let noArgs = try #require(
      RuntimeMethod.methods(of: RKFixture.self).first { $0.selectorName == "noArgs" })
    // Full method encoding: return type, then `@` (self), `:` (_cmd) with offsets.
    #expect(noArgs.typeEncoding.contains("@"))
    #expect(noArgs.typeEncoding.contains(":"))
    #expect(!noArgs.typeEncoding.isEmpty)
  }

  @Test
  func `instance methods do not include the class method`() {
    let instanceSelectors = Set(RuntimeMethod.methods(of: RKFixture.self).map(\.selectorName))
    #expect(!instanceSelectors.contains("classGreeting"))
  }

  @Test
  func `classMethods reflects the metaclass and finds the class method`() {
    let classSelectors = Set(RuntimeMethod.classMethods(of: RKFixture.self).map(\.selectorName))
    #expect(classSelectors.contains("classGreeting"))
    // And the instance methods must not leak into the class-method list.
    #expect(!classSelectors.contains("takesOne:"))
  }

  @Test
  func `reflecting a Foundation class finds well-known selectors`() {
    // A second oracle: NSObject's own instance methods include `description`.
    let selectors = Set(RuntimeMethod.methods(of: NSObject.self).map(\.selectorName))
    #expect(selectors.contains("description"))
  }
}
