import Foundation
import UIToolCore

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

// SPEC: domain.uitool.injection
/// The live source — the deferred injected-server client. Constructing it is fine
/// (a verb resolves it before knowing whether a session exists); using it is what
/// is gated: `load()` throws `NOT_ATTACHED` (exit 4) because the injection half
/// (`UIToolServer` / `UIToolBoot`) that would answer over the socket is not yet
/// built. The error is clean and branchable, never a fake snapshot or a crash.
struct SessionSnapshotSource: SnapshotSource {
  let app: String

  func load() throws -> Capture {
    throw UIToolError.notAttached
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
