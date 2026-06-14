import Foundation
import TestSupport
import Testing
import UIToolCore

@testable import UIToolServer

// SPEC: command.uitool.inspect
//
// The object-inspector oracle: a fixture NSObject with known ivars, reflected
// in-process (no socket, no injection). Pins the value-fetching read RuntimeKit
// leaves out — scalar ivars read from memory, an object ivar normalized to
// {class}, plus the class reflection (properties/methods/protocols). Getter
// invocation (--invoke) is a later slice and not exercised here.

@objc(UIToolInspectFixture)
private final class InspectFixture: NSObject {
  @objc let count: Int = 42
  @objc let ratio: Double = 1.5
  @objc let enabled: Bool = true
  @objc let held: NSObject = NSObject()
}

@Suite(.spec("command.uitool.inspect"))
@MainActor
struct ObjectInspectorTests {

  private func valueOfIvar(_ result: InspectResult, named name: String) -> JSONValue? {
    result.ivars.first { $0.name == name }?.value
  }

  @Test func `inspect reports the runtime class and the node id it was read through`() {
    let result = ObjectInspector.inspect(InspectFixture(), nodeID: "7:w0/cv/x0")
    #expect(result.node == "7:w0/cv/x0")
    #expect(result.class.contains("InspectFixture"))
  }

  @Test func `inspect reads scalar ivar values from memory`() {
    let result = ObjectInspector.inspect(InspectFixture(), nodeID: "7:w0")
    // The exact ivar names are Swift's, but the values must be readable: 42, 1.5, true.
    #expect(result.ivars.contains { $0.value == .number(42) })
    #expect(result.ivars.contains { $0.value == .number(1.5) })
    #expect(result.ivars.contains { $0.value == .bool(true) || $0.value == .number(1) })
  }

  @Test func `inspect reads an object ivar as its class, never a pointer`() {
    let result = ObjectInspector.inspect(InspectFixture(), nodeID: "7:w0")
    let objectIvar = result.ivars.first {
      if case .object(let fields) = $0.value, fields["class"] != nil { return true }
      return false
    }
    #expect(objectIvar != nil, "the held NSObject ivar reads as {class}")
    if case .object(let fields)? = objectIvar?.value {
      #expect(fields["class"] == .string("NSObject"))
      #expect(fields["node"] == nil)  // no registry resolver in this slice
    }
  }

  @Test func `inspect carries class reflection (properties/methods/protocols) without values`() {
    let result = ObjectInspector.inspect(InspectFixture(), nodeID: "7:w0")
    // No --invoke in this slice, so no property carries a value.
    #expect(result.properties.allSatisfy { $0.value == nil })
    // Methods/protocols come from the class reflection and are sorted.
    #expect(result.methods == result.methods.sorted())
    #expect(result.protocols == result.protocols.sorted())
  }

  @Test func `a match narrows the reported ivars by name`() {
    let result = ObjectInspector.inspect(
      InspectFixture(), nodeID: "7:w0", matching: { $0.contains("count") })
    #expect(result.ivars.allSatisfy { $0.name.contains("count") })
    #expect(result.ivars.contains { $0.value == .number(42) })
  }
}
