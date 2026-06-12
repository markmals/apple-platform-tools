import Foundation
import RuntimeKit
import Testing
import UIToolCore

@testable import uitool

// SPEC: domain.uitool.ipc
//
// The shared-shell oracle for the uitool CLI: the offline Capture envelope round-
// trips through JSON, the two SnapshotSource implementations behave (FileSnapshot
// loads a written fixture; SessionSnapshot is gated to NOT_ATTACHED), resolveSource
// picks the right source from the flags, and the response envelope encodes the
// IPC-contracted keys with --no-meta stripping the suppressible ones. Pure values,
// no live process, no socket, no injection.

// MARK: - fixtures

/// A leaf window with a one-view content tree — the smallest valid Capture body.
private func sampleWindow() -> WindowSnapshot {
  let contentView = ViewSnapshot(
    runtimeClass: "NSView",
    superclasses: ["NSResponder", "NSObject"],
    frame: Rect(x: 0, y: 0, width: 400, height: 300),
    frameTopLeft: Rect(x: 0, y: 0, width: 400, height: 300),
    isFlipped: false,
    hidden: false,
    alpha: 1,
    identifier: nil,
    text: nil,
    axRole: nil,
    font: nil,
    material: nil,
    blendingMode: nil,
    layer: nil,
    constraints: nil,
    swiftUIBoundary: false,
    childCount: 0,
    truncated: false,
    children: [])
  return WindowSnapshot(
    runtimeClass: "NSWindow",
    title: "Inbox",
    identifier: nil,
    isKey: true,
    isMain: true,
    isVisible: true,
    isPanel: false,
    frame: Rect(x: 0, y: 0, width: 400, height: 300),
    contentView: contentView,
    childWindows: [])
}

// MARK: - Capture round-trip

// SPEC: domain.uitool.ipc
@Test func `a Capture round-trips through JSON`() throws {
  let capture = Capture(epoch: 7, windows: [sampleWindow()])
  let data = try JSONEncoder().encode(capture)
  let decoded = try JSONDecoder().decode(Capture.self, from: data)

  #expect(decoded.epoch == 7)
  #expect(decoded.windows.count == 1)
  #expect(decoded.windows.first?.title == "Inbox")
  #expect(decoded.windows.first?.contentView?.runtimeClass == "NSView")
}

// MARK: - SnapshotSource

// SPEC: command.uitool.windows
@Test func `FileSnapshotSource loads a written fixture`() throws {
  let capture = Capture(epoch: 3, windows: [sampleWindow()])
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("uitool-shell-\(UUID().uuidString).json")
  try JSONEncoder().encode(capture).write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let loaded = try FileSnapshotSource(path: url.path).load()
  #expect(loaded.epoch == 3)
  #expect(loaded.windows.count == 1)
}

// SPEC: command.uitool.windows
@Test func `FileSnapshotSource on a missing file is a clean usage error`() {
  #expect(throws: UIToolError.badSelector("cannot read snapshot file: /no/such/path.json")) {
    try FileSnapshotSource(path: "/no/such/path.json").load()
  }
}

// SPEC: domain.uitool.injection
@Test func `SessionSnapshotSource is gated to NOT_ATTACHED`() {
  #expect(throws: UIToolError.notAttached) {
    try SessionSnapshotSource(app: "com.apple.mail").load()
  }
}

// SPEC: command.uitool.windows
@Test func `resolveSource prefers the snapshot file when given`() throws {
  let source = try resolveSource(snapshot: "/tmp/cap.json", app: "com.apple.mail")
  #expect(source is FileSnapshotSource)
}

// SPEC: command.uitool.windows
@Test func `resolveSource falls back to the gated session for a named app`() throws {
  let source = try resolveSource(snapshot: nil, app: "com.apple.mail")
  #expect(source is SessionSnapshotSource)
}

// SPEC: command.uitool.windows
@Test func `resolveSource with neither target is a usage error`() {
  #expect(throws: UIToolError.self) {
    _ = try resolveSource(snapshot: nil, app: nil)
  }
}

// MARK: - ResponseEnvelope

// SPEC: domain.uitool.ipc
@Test func `the envelope encodes schemaVersion sessionId and _meta`() throws {
  let meta = ResponseMeta(returned: 2, truncated: true, totalMatched: 5)
  let envelope = ResponseEnvelope.forList(sessionId: "7", meta: meta, noMeta: false)
  let line = try envelope.line()

  #expect(line.contains("\"schemaVersion\":\"1.0.0\""))
  #expect(line.contains("\"sessionId\":\"7\""))
  #expect(line.contains("\"_meta\":{\"returned\":2,\"totalMatched\":5,\"truncated\":true}"))
}

// SPEC: domain.uitool.ipc
@Test func `--no-meta strips sessionId and _meta but never schemaVersion`() throws {
  let meta = ResponseMeta(returned: 2, truncated: true, totalMatched: 5)
  let envelope = ResponseEnvelope.forList(sessionId: "7", meta: meta, noMeta: true)
  let line = try envelope.line()

  #expect(line.contains("\"schemaVersion\":\"1.0.0\""))
  #expect(!line.contains("sessionId"))
  #expect(!line.contains("_meta"))
}
