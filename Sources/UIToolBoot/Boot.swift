import Foundation
import UIToolCore
import UIToolIPC
import UIToolServer

// SPEC: domain.uitool.boot
/// The boot dylib's Swift entry point. The dylib is loaded into a target — via
/// `DYLD_INSERT_LIBRARIES` at launch ([[command.uitool.launch]]) or a remote
/// `dlopen` at attach ([[command.uitool.attach]]) — and an image-load shim
/// (`UIToolBootCtor`'s ObjC `+load`) calls this. It derives the per-pid socket
/// path, starts the `SocketServer` (which owns its own background accept thread, so
/// this returns immediately), and retains it for the process lifetime.
///
/// Discipline ([[domain.uitool.boot]] constructor contract): **non-blocking**,
/// touches **no AppKit** on the loading thread, and never crashes the host — a
/// bind failure simply leaves no socket, which the CLI's bounded poll surfaces as
/// `INJECTION_FAILED`.
@_cdecl("uitool_boot_start")
public func uitool_boot_start() {
  // Idempotent: a second load (re-inject into an already-served target) reuses the
  // running server rather than binding a second socket.
  guard bootServer == nil else { return }

  let path = UnixSocket.path(forPID: getpid())
  // Each boot is one session. A wall-clock epoch differs across re-injections, so
  // handles minted in a prior (detached, re-injected) session read as stale.
  let epoch = Int(Date().timeIntervalSince1970)
  let server = SocketServer(socketPath: path, handler: makeBoundedHandler(epoch: epoch))
  do {
    try server.start()
    bootServer = server
  } catch {
    // No server bound; the host runs on untouched. The CLI times out its poll and
    // reports INJECTION_FAILED rather than ever claiming success.
  }
}

/// Retains the server for the process lifetime. Written once on the loading thread
/// before any other thread can observe it; `nonisolated(unsafe)` is the honest
/// annotation for a load-time-initialized global.
nonisolated(unsafe) private var bootServer: SocketServer?
