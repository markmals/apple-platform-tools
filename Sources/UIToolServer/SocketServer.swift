import Foundation
import UIToolCore
import UIToolIPC

// SPEC: domain.uitool.ipc
/// The server's socket transport. It binds `/tmp/uitool-<pid>.sock`, accepts
/// connections on a dedicated **background** thread (never the host main thread —
/// [[domain.uitool.ipc]] threading), and for each newline-framed request calls the
/// injected `handler` and writes its response line. The handler is supplied by the
/// boot dylib as the bounded main-thread hop around `RequestHandler`
/// (`makeBoundedHandler`); `SocketServer` itself is pure transport, so it is
/// testable over a loopback with a trivial handler.
public final class SocketServer: @unchecked Sendable {
  private let socketPath: String
  private let handler: @Sendable (WireRequest) -> String
  private var listeningFD: Int32 = -1
  private var thread: Thread?

  public init(socketPath: String, handler: @escaping @Sendable (WireRequest) -> String) {
    self.socketPath = socketPath
    self.handler = handler
  }

  /// Bind + listen, then run the accept loop on a background thread. Throws if the
  /// socket cannot be bound (the caller surfaces injection failure).
  public func start() throws {
    listeningFD = try UnixSocket.listen(path: socketPath)
    let thread = Thread { [weak self] in self?.acceptLoop() }
    thread.name = "uitool.server"
    self.thread = thread
    thread.start()
  }

  /// Close the listening socket (which unblocks `accept` and ends the loop) and
  /// unlink the path ([[domain.uitool.ipc]] threading: on unload close + unlink).
  public func stop() {
    let fd = listeningFD
    listeningFD = -1
    if fd >= 0 { UnixSocket.close(fd) }
    unlink(socketPath)
  }

  private func acceptLoop() {
    while listeningFD >= 0 {
      guard let connectionFD = try? UnixSocket.accept(listeningFD) else { return }
      serve(connectionFD: connectionFD)
    }
  }

  /// Serve one connection: decode each request line, hand it to the handler, write
  /// the response, until the peer closes. A garbled line is skipped (it carries no
  /// id to answer against) rather than killing the connection.
  private func serve(connectionFD: Int32) {
    let connection = LineConnection(fd: connectionFD)
    defer { UnixSocket.close(connectionFD) }
    while let lineData = connection.readLine() {
      guard let request = try? JSONDecoder().decode(WireRequest.self, from: lineData) else {
        continue
      }
      try? connection.write(line: handler(request))
    }
  }
}
