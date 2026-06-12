import Foundation
import RuntimeKit
import Testing
import UIToolCore

@testable import uitool

// SPEC: command.uitool.windows
// SPEC: command.uitool.tree
// SPEC: command.uitool.find
// SPEC: command.uitool.node
//
// The read-verb oracle for the uitool CLI: a Capture fixture is written to a temp
// file, then each verb is driven over the same source-resolution seam the commands
// use (loadTree → Verbs.<verb>) and its emitted JSON asserted. windows lists window
// records; find with a class selector locates the node; tree --depth truncates; node
// --at resolves and a bogus id fails; a live <app> with no --snapshot is NOT_ATTACHED.
// Pure values from a captured forest — no live process, no socket, no injection.

// MARK: - fixture

/// A two-level content tree under one window: an `NSStackView` content view holding
/// an `NSButton` and an `NSTextField`, the button itself wrapping an `NSImageView`.
/// Deep enough that `tree --depth` can cut a branch and a class selector can locate a
/// single typed node among siblings.
private func sampleCapture(epoch: Int = 7) -> Capture {
  let imageView = view(class: "NSImageView", x: 4, y: 4, w: 16, h: 16)
  let button = view(class: "NSButton", x: 8, y: 8, w: 80, h: 24, children: [imageView])
  let field = view(class: "NSTextField", x: 8, y: 40, w: 200, h: 18)
  let contentView = view(
    class: "NSStackView", x: 0, y: 0, w: 400, h: 300, children: [button, field])
  let window = WindowSnapshot(
    runtimeClass: "NSWindow", title: "Inbox", identifier: nil, isKey: true, isMain: true,
    isVisible: true, isPanel: false, frame: Rect(x: 0, y: 0, width: 400, height: 300),
    contentView: contentView, childWindows: [])
  return Capture(epoch: epoch, windows: [window])
}

private func view(
  class cls: String, x: Double, y: Double, w: Double, h: Double,
  children: [ViewSnapshot] = []
) -> ViewSnapshot {
  ViewSnapshot(
    runtimeClass: cls, superclasses: ["NSView", "NSResponder", "NSObject"],
    frame: Rect(x: x, y: y, width: w, height: h),
    frameTopLeft: Rect(x: x, y: y, width: w, height: h),
    isFlipped: false, hidden: false, alpha: 1, identifier: nil, text: nil, axRole: nil,
    font: nil, material: nil, blendingMode: nil, layer: nil, constraints: nil,
    swiftUIBoundary: false, childCount: children.count, truncated: false, children: children)
}

/// Write a Capture to a unique temp file and return its path; the caller removes it.
private func writeCapture(_ capture: Capture) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("uitool-readverb-\(UUID().uuidString).json")
  try JSONEncoder().encode(capture).write(to: url)
  return url
}

// MARK: - windows

// SPEC: command.uitool.windows
@Test func `windows lists one record per window over a snapshot`() throws {
  let url = try writeCapture(sampleCapture())
  defer { try? FileManager.default.removeItem(at: url) }

  let resolved = try loadTree(snapshot: url.path, app: nil)
  let result = try Verbs.windows(resolved.tree)

  #expect(result.returned == 1)
  #expect(result.totalMatched == 1)
  #expect(resolved.sessionId == "7")
  let record = try #require(result.lines.first)
  #expect(record.contains("\"node\":\"7:w0\""))
  #expect(record.contains("\"class\":\"NSWindow\""))
  #expect(record.contains("\"title\":\"Inbox\""))
  #expect(record.contains("\"parent\":null"))
}

// MARK: - find

// SPEC: command.uitool.find
@Test func `find with a class selector locates the single matching node`() throws {
  let url = try writeCapture(sampleCapture())
  defer { try? FileManager.default.removeItem(at: url) }

  let resolved = try loadTree(snapshot: url.path, app: nil)
  let selector = try Selector(parsing: "NSButton")
  let result = try Verbs.find(in: resolved.tree, selector: selector)

  #expect(result.totalMatched == 1)
  #expect(result.returned == 1)
  let record = try #require(result.lines.first)
  #expect(record.contains("\"class\":\"NSButton\""))
  #expect(record.contains("\"node\":\"7:w0/cv/b0\""))
}

// SPEC: command.uitool.find
@Test func `find with neither selector nor predicate is a usage error`() throws {
  let url = try writeCapture(sampleCapture())
  defer { try? FileManager.default.removeItem(at: url) }
  let resolved = try loadTree(snapshot: url.path, app: nil)

  #expect(throws: UIToolError.self) {
    _ = try Verbs.find(in: resolved.tree)
  }
}

// MARK: - tree

// SPEC: command.uitool.tree
@Test func `tree --depth cuts a branch and marks it truncated`() throws {
  let url = try writeCapture(sampleCapture())
  defer { try? FileManager.default.removeItem(at: url) }
  let resolved = try loadTree(snapshot: url.path, app: nil)
  let root = try #require(NodeID(parsing: "7:w0/cv"))

  // Depth 1: the content view's children (button, field) are emitted, but the
  // button's NSImageView grandchild sits at the floor — the button is cut, carrying
  // the per-node depth-cut marker (truncated:true + childCount) on its own record.
  let result = try Verbs.tree(at: root, in: resolved.tree, maxDepth: 1)

  let buttonLine = try #require(result.lines.first { $0.contains("\"class\":\"NSButton\"") })
  #expect(buttonLine.contains("\"truncated\":true"))
  #expect(buttonLine.contains("\"childCount\":1"))
  // The deeper NSImageView is past the depth floor and never emitted.
  #expect(!result.lines.contains { $0.contains("\"class\":\"NSImageView\"") })
  // The leaf NSTextField is emitted and is never marked truncated.
  let fieldLine = try #require(result.lines.first { $0.contains("\"class\":\"NSTextField\"") })
  #expect(!fieldLine.contains("\"truncated\":true"))
}

// MARK: - node

// SPEC: command.uitool.node
@Test func `node --at resolves a single node to a scalar object`() throws {
  let url = try writeCapture(sampleCapture())
  defer { try? FileManager.default.removeItem(at: url) }
  let resolved = try loadTree(snapshot: url.path, app: nil)
  let id = try #require(NodeID(parsing: "7:w0/cv/b0"))

  let json = try Verbs.node(at: id, in: resolved.tree)

  #expect(json.contains("\"class\" : \"NSButton\""))
  #expect(json.contains("\"node\" : \"7:w0/cv/b0\""))
  // A scalar object, not a JSON-Lines stream: one object, no trailing envelope line.
  #expect(!json.contains("\n{"))
}

@Test func `node carries the top-level sessionId unless --no-meta suppresses it`() throws {
  let url = try writeCapture(sampleCapture())
  defer { try? FileManager.default.removeItem(at: url) }
  let resolved = try loadTree(snapshot: url.path, app: nil)
  let id = try #require(NodeID(parsing: "7:w0/cv/b0"))

  // The scalar node payload carries the IPC envelope's sessionId inline (no _meta).
  let withMeta = try Verbs.node(at: id, in: resolved.tree, sessionId: resolved.sessionId)
  #expect(withMeta.contains("\"sessionId\" : \"7\""))
  // --no-meta passes nil → byte-stable across sessions.
  let suppressed = try Verbs.node(at: id, in: resolved.tree, sessionId: nil)
  #expect(!suppressed.contains("sessionId"))
}

// SPEC: command.uitool.node
@Test func `node --at on a bogus id fails STALE_NODE`() throws {
  let url = try writeCapture(sampleCapture())
  defer { try? FileManager.default.removeItem(at: url) }
  let resolved = try loadTree(snapshot: url.path, app: nil)
  let bogus = try #require(NodeID(parsing: "7:w0/cv/zz9"))

  #expect(throws: UIToolError.self) {
    _ = try Verbs.node(at: bogus, in: resolved.tree)
  }
  // Specifically the stale-node code, exit 5 — not a silent empty read.
  do {
    _ = try Verbs.node(at: bogus, in: resolved.tree)
    Issue.record("expected a stale-node failure")
  } catch let error as UIToolError {
    #expect(error.code == "STALE_NODE")
    #expect(error.exitCode == 5)
  }
}

// MARK: - source gating

// SPEC: domain.uitool.injection
@Test func `a live app with no --snapshot fails NOT_ATTACHED`() {
  #expect(throws: UIToolError.notAttached) {
    _ = try loadTree(snapshot: nil, app: "com.apple.mail")
  }
  do {
    _ = try loadTree(snapshot: nil, app: "com.apple.mail")
    Issue.record("expected NOT_ATTACHED")
  } catch let error as UIToolError {
    #expect(error.code == "NOT_ATTACHED")
    #expect(error.exitCode == 4)
  } catch {
    Issue.record("expected a UIToolError, got \(error)")
  }
}
