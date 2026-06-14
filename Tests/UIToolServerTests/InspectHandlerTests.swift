import AppKit
import Foundation
import SampleAppKit
import TestSupport
import Testing
import UIToolCore

@testable import UIToolServer

// SPEC: command.uitool.inspect
//
// The inspect-op oracle: the SampleAppKit scene in-process, driven through
// RequestHandler.inspect. Pins node-id -> live-view resolution (the registry's
// re-walk), the inspect of the resolved view, and STALE_NODE on a bad epoch or an
// unresolvable path. @MainActor + a window-server session, like the walker layer.
// The window index is computed (other test windows may share NSApp), so w<n> is
// unambiguous.

@Suite(.spec("command.uitool.inspect"))
@MainActor
struct InspectHandlerTests {

  /// The index of the oracle's main window among the top-level windows — the `w<n>`
  /// basis LiveTreeResolver uses.
  private func mainWindowIndex() throws -> Int {
    let top = NSApplication.shared.windows.filter { $0.parent == nil && $0.sheetParent == nil }
    return try #require(top.firstIndex { $0.title == SampleScene.Known.mainTitle })
  }

  @Test func `inspect resolves a node id to its live view and reflects it`() throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let index = try mainWindowIndex()
    let nodeID = "7:w\(index)/cv/vev0"  // the sidebar NSVisualEffectView
    let response = RequestHandler.inspect(WireRequest(id: 1, op: "inspect", node: nodeID), epoch: 7)
    let result = try #require(response.data)
    #expect(response.ok)
    #expect(result.class == "NSVisualEffectView")
    #expect(result.node == nodeID)
    // It reflects real members — NSVisualEffectView declares a `material` property.
    #expect(result.properties.contains { $0.name == "material" })
  }

  @Test func `a node id from a stale epoch is STALE_NODE`() {
    let response = RequestHandler.inspect(
      WireRequest(id: 2, op: "inspect", node: "999:w0/cv"), epoch: 7)
    #expect(!response.ok)
    #expect(response.error?.code == "STALE_NODE")
  }

  @Test func `a node id whose path no longer resolves is STALE_NODE`() throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }
    let index = try mainWindowIndex()
    let response = RequestHandler.inspect(
      WireRequest(id: 3, op: "inspect", node: "7:w\(index)/cv/zz9"), epoch: 7)
    #expect(response.error?.code == "STALE_NODE")
  }

  @Test func `inspect with no node id is a usage error`() {
    let response = RequestHandler.inspect(WireRequest(id: 4, op: "inspect"), epoch: 7)
    #expect(!response.ok)
    #expect(response.error?.code == "BAD_SELECTOR")
  }
}
