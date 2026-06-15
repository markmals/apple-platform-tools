import AgentCLI
import Foundation
import RuntimeKit
import TestSupport
import Testing

@testable import UIToolCore

// SPEC: command.uitool.schema
//
// The schema contract is authored data; these pin its shape, its determinism, and
// — the drift guard — that every field the node verb actually emits is documented.

@Suite(.spec("command.uitool.schema"))
struct SchemaTests {

  @Test(.scenario("scenario.uitool.schema-print.node-fields"))
  func `the node record marks default and include fields`() throws {
    let node = try #require(SchemaCatalog.contract().records["node"])
    let names = Set(node.fields.map(\.name))
    #expect(names.isSuperset(of: ["node", "class", "frame", "childCount"]))

    let layer = try #require(node.fields.first { $0.name == "layer" })
    #expect(!layer.default)
    #expect(layer.include == "layer")
    let cls = try #require(node.fields.first { $0.name == "class" })
    #expect(cls.default)
  }

  @Test func `the exit-code map covers the closed set`() {
    let codes = SchemaCatalog.contract().exitCodes
    #expect(codes["5"]?.contains("STALE_NODE") == true)
    #expect(Set(codes.keys).isSuperset(of: ["0", "2", "3", "4", "5", "6", "7", "8"]))
  }

  @Test(.scenario("scenario.uitool.schema-print.deterministic"))
  func `the contract encodes deterministically`() throws {
    #expect(try Output.line(SchemaCatalog.contract()) == Output.line(SchemaCatalog.contract()))
  }

  @Test func `every field the node verb emits is documented in the schema`() throws {
    // Build one node with non-null facets so the default projection emits its keys,
    // then assert the schema's node record documents every emitted key — a drift
    // guard between the contract and the actual Node projection.
    let leaf = ViewSnapshot(
      runtimeClass: "NSView", superclasses: ["NSResponder", "NSObject"],
      frame: Rect(x: 0, y: 0, width: 10, height: 10),
      frameTopLeft: Rect(x: 0, y: 0, width: 10, height: 10),
      isFlipped: false, hidden: false, alpha: 1, identifier: "x", text: "t", axRole: "AXGroup",
      font: nil, material: nil, blendingMode: nil, layer: nil, constraints: nil,
      swiftUIBoundary: false, childCount: 0, truncated: false, children: [])
    let window = WindowSnapshot(
      runtimeClass: "NSWindow", title: "T", identifier: nil, isKey: true, isMain: true,
      isVisible: true, isPanel: false, frame: Rect(x: 0, y: 0, width: 1, height: 1),
      contentView: leaf, childWindows: [])
    let tree = NodeTree(windows: [window], epoch: 7)
    let json = try Verbs.node(at: NodeID(epoch: 7, structuralPath: "w0/cv"), in: tree)
    let object = try #require(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

    let documented = Set(SchemaCatalog.contract().records["node"]!.fields.map(\.name))
    let emitted = Set(object.keys)
    #expect(
      emitted.isSubset(of: documented), "undocumented node keys: \(emitted.subtracting(documented))"
    )
  }
}
