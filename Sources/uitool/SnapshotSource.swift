import AppKit
import Foundation
import UIToolCore
import UIToolIPC

// SPEC: domain.uitool.ipc
/// Where a read verb gets its window forest. The MVP source is **offline** — a
/// captured `Capture` JSON on disk — so the four read verbs (`windows` / `tree` /
/// `find` / `node`) run with no live process and no socket. The **live** source
/// (attach to a running app over the injected `UIToolServer` socket) is the
/// deferred injection half: its `load()` throws `NOT_ATTACHED` noting the
/// injection half is not yet built. Both produce a `Capture`, so a verb resolves
/// one source and never branches on which it got.
protocol SnapshotSource {
  func load() throws -> Capture
}

// SPEC: command.uitool.windows
/// The offline source: reads and JSON-decodes a `Capture` from `--snapshot
/// <path>`. A missing or garbled file is a clean usage error (exit 2), not a
/// crash — the path is external input, validated at the boundary.
struct FileSnapshotSource: SnapshotSource {
  let path: String

  func load() throws -> Capture {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
      throw UIToolError.badSelector("cannot read snapshot file: \(path)")
    }
    do {
      return try JSONDecoder().decode(Capture.self, from: data)
    } catch {
      throw UIToolError.badSelector("malformed snapshot file: \(path)")
    }
  }
}

// SPEC: domain.uitool.ipc
/// The live source: connect to the target's session socket, perform the `ping`
/// handshake (rejecting a schema skew, exit 8), and fetch the window-forest
/// `Capture` the read verbs run over — the dumb-server design, so the same verbs
/// that drive the offline `--snapshot` source drive the live one
/// ([[domain.uitool.server]]). A target with no live session (the socket refuses)
/// surfaces as `NOT_ATTACHED` (exit 4), never a fake snapshot.
struct SessionSnapshotSource: SnapshotSource {
  let app: String

  func load() throws -> Capture {
    let client = try IPCClient.connect(socketPath: try Self.socketPath(for: app))
    defer { client.close() }
    try client.handshake()
    // The full forest; the pure verbs navigate and prune over the Capture.
    return try client.fetchCapture()
  }

  /// Resolve `<app>` (a pid or a bundle id) to its `/tmp/uitool-<pid>.sock` path.
  /// A bundle id with no running instance has no session, so it is `NOT_ATTACHED`.
  static func socketPath(for app: String) throws -> String {
    if let pid = Int32(app) {
      return UnixSocket.path(forPID: pid)
    }
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: app)
    guard let pid = running.first?.processIdentifier else {
      throw UIToolError.notAttached
    }
    return UnixSocket.path(forPID: pid)
  }
}

// SPEC: command.uitool.windows
/// Pick a read verb's source from its flags: `--snapshot <path>` selects the
/// offline file source; otherwise a named `<app>` selects the gated live session
/// source. Neither given is a usage error (exit 2) — a read verb needs a target.
func resolveSource(snapshot: String?, app: String?) throws -> SnapshotSource {
  if let snapshot {
    return FileSnapshotSource(path: snapshot)
  }
  if let app {
    return SessionSnapshotSource(app: app)
  }
  throw UIToolError.badSelector("a target <app> or --snapshot <path> is required")
}
