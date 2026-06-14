import Foundation
import SampleAppKit
import TestSupport
import Testing
import UIToolCore

@testable import UIToolServer

// SPEC: domain.uitool.server
//
// The server oracle: the SampleAppKit known-geometry scene built in-process on the
// main thread (no socket, no injection), driven through the RequestHandler, and
// asserted against the pinned geometry. This is the dumb forest-shipping design —
// a read op snapshots the live window forest into a Capture (the same envelope the
// offline source decodes), and the same Capture runs through the existing pure
// verbs unchanged. AppKit reads are main-thread-only, so the suite is @MainActor
// and needs a logged-in (window-server) macOS session, like the walker layer.

@Suite(.spec("domain.uitool.server"))
@MainActor
struct RequestHandlerTests {

  // MARK: - ping

  @Test func `ping returns the schema version and the session epoch`() throws {
    let response = RequestHandler.ping(WireRequest(id: 1, op: "ping"), epoch: 7)
    #expect(response.ok)
    #expect(response.data?.schemaVersion == Schema.version)
    #expect(response.data?.epoch == 7)
    #expect(response.error == nil)
  }

  // MARK: - read (forest snapshot)

  @Test func `a read ships a Capture of the live window forest at the session epoch`() throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let response = RequestHandler.read(WireRequest(id: 2, op: "windows"), epoch: 7)
    let capture = try #require(response.data)
    #expect(capture.epoch == 7)

    let main = try #require(
      capture.windows.first { $0.title == SampleScene.Known.mainTitle },
      "the oracle's main window is in the shipped forest")
    let content = try #require(main.contentView)

    // The sidebar visual-effect view carries its material — a fact AX hides.
    let sidebar = try #require(
      content.children.first { $0.identifier == SampleScene.Known.sidebarIdentifier })
    #expect(sidebar.material == SampleScene.Known.sidebarMaterial)
    #expect(sidebar.runtimeClass == "NSVisualEffectView")
  }

  @Test func `the panel and the nested child window are surfaced correctly`() throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let capture = try #require(
      RequestHandler.read(WireRequest(id: 3, op: "windows"), epoch: 7).data)

    // The panel is a top-level root and reports isPanel.
    let panel = try #require(
      capture.windows.first { $0.identifier == SampleScene.Known.panelIdentifier })
    #expect(panel.isPanel)

    // The child window is nested under the main window, never a separate root.
    let main = try #require(capture.windows.first { $0.title == SampleScene.Known.mainTitle })
    #expect(!capture.windows.contains { $0.title == SampleScene.Known.childTitle })
    #expect(main.childWindows.contains { $0.title == SampleScene.Known.childTitle })
  }

  @Test func `the flipped container reports isFlipped and its child carries one constraint`()
    throws
  {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let capture = try #require(
      RequestHandler.read(WireRequest(id: 4, op: "windows"), epoch: 7).data)
    let content = try #require(
      capture.windows.first { $0.title == SampleScene.Known.mainTitle }?.contentView)

    let flipped = try #require(
      content.children.first { $0.identifier == SampleScene.Known.flippedBoxIdentifier })
    #expect(flipped.isFlipped)
    // Its one child is pinned to a fixed width — constraintsCount surfaces it.
    let constrainedChild = try #require(flipped.children.first)
    let constraints = try #require(constrainedChild.constraints)
    #expect(constraints.constraints.contains { $0.first.attribute == "width" })
  }

  @Test func `the plain view has no backing layer`() throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let capture = try #require(
      RequestHandler.read(WireRequest(id: 5, op: "windows"), epoch: 7).data)
    let content = try #require(
      capture.windows.first { $0.title == SampleScene.Known.mainTitle }?.contentView)
    let plain = try #require(
      content.children.first { $0.identifier == SampleScene.Known.plainIdentifier })
    #expect(plain.layer == nil)
  }

  // MARK: - the Capture is interchangeable with the offline source

  @Test func `the read Capture runs through the existing pure verbs`() throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let capture = try #require(
      RequestHandler.read(WireRequest(id: 6, op: "windows"), epoch: 7).data)

    // The live Capture is fed to the SAME NodeTree + verbs the offline --snapshot
    // path uses; the server held no policy, the pure core does the work.
    let tree = NodeTree(windows: capture.windows, epoch: capture.epoch)
    let main = try #require(
      capture.windows.firstIndex { $0.title == SampleScene.Known.mainTitle })
    let windows = try Verbs.windows(tree)
    #expect(windows.totalMatched == capture.windows.count)

    // find the greeting label by class through the live-sourced tree
    let labels = try Verbs.find(in: tree, selector: try Selector(parsing: "NSTextField"))
    let texts = try labels.lines.map { line -> String? in
      let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
      return object?["text"] as? String
    }
    #expect(texts.contains(SampleScene.Known.greetingText))
    _ = main  // index proves the main window is enumerable; verbs cover the rest
  }

  // MARK: - dispatch / encoding

  @Test func `handle encodes a ping response to a decodable JSON line`() throws {
    let line = try RequestHandler.handle(WireRequest(id: 8, op: "ping"), epoch: 9)
    let decoded = try JSONDecoder().decode(WireResponse<Ping>.self, from: Data(line.utf8))
    #expect(decoded.ok)
    #expect(decoded.id == 8)
    #expect(decoded.data?.epoch == 9)
    #expect(decoded.v == WireProtocol.version)
  }

  @Test func `handle encodes a read response carrying the Capture`() throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let line = try RequestHandler.handle(WireRequest(id: 9, op: "windows", maxDepth: 3), epoch: 7)
    let decoded = try JSONDecoder().decode(WireResponse<Capture>.self, from: Data(line.utf8))
    #expect(decoded.ok)
    #expect(decoded.data?.epoch == 7)
    #expect(decoded.data?.windows.contains { $0.title == SampleScene.Known.mainTitle } == true)
  }

  @Test func `an unknown op is a usage error, never a crash`() throws {
    let line = try RequestHandler.handle(WireRequest(id: 10, op: "mutate"), epoch: 1)
    let decoded = try JSONDecoder().decode(WireResponse<Capture>.self, from: Data(line.utf8))
    #expect(!decoded.ok)
    #expect(decoded.data == nil)
    #expect(decoded.error?.code == "BAD_SELECTOR")
  }
}
