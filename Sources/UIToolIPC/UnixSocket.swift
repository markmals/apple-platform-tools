import Darwin
import Foundation

// SPEC: domain.uitool.ipc
/// POSIX unix-domain-socket primitives shared by the injected server and the CLI
/// client. The v1 transport is a Unix domain socket (rejected: Mach ports for
/// bootstrap friction, localhost TCP because any local process could connect —
/// [[domain.uitool.ipc]]). Thin wrappers over Darwin's socket API; the newline
/// framing lives in `LineConnection`.
public enum UnixSocket {
  public enum SocketError: Error, Equatable {
    case create(Int32)
    case bind(Int32)
    case listen(Int32)
    case accept(Int32)
    case connect(Int32)
    case pathTooLong
  }

  /// Bind a listening stream socket at `path`, `chmod 0600`, removing any stale
  /// node first (a leftover socket from a crashed session is not reusable —
  /// [[domain.uitool.boot]]). Returns the listening fd.
  public static func listen(path: String, backlog: Int32 = 16) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw SocketError.create(errno) }
    unlink(path)
    var addr = try address(for: path)
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, length) }
    }
    guard bound == 0 else {
      let e = errno
      close(fd)
      throw SocketError.bind(e)
    }
    chmod(path, 0o600)
    guard Darwin.listen(fd, backlog) == 0 else {
      let e = errno
      close(fd)
      throw SocketError.listen(e)
    }
    return fd
  }

  /// Accept one connection on `listeningFD`; throws when the listener is closed
  /// (the signal the accept loop uses to exit).
  public static func accept(_ listeningFD: Int32) throws -> Int32 {
    let fd = Darwin.accept(listeningFD, nil, nil)
    guard fd >= 0 else { throw SocketError.accept(errno) }
    return fd
  }

  /// Connect a stream socket to `path`; throws `connect` on refusal — no listener,
  /// i.e. no live session ([[domain.uitool.injection]] → `NOT_ATTACHED`).
  public static func connect(path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw SocketError.create(errno) }
    var addr = try address(for: path)
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
    }
    guard connected == 0 else {
      let e = errno
      close(fd)
      throw SocketError.connect(e)
    }
    return fd
  }

  public static func close(_ fd: Int32) { _ = Darwin.close(fd) }

  /// The per-session socket path: `/tmp/uitool-<pid>.sock` ([[domain.uitool.ipc]]).
  public static func path(forPID pid: Int32) -> String {
    "/tmp/uitool-\(pid).sock"
  }

  /// Build a `sockaddr_un` for `path`, rejecting an over-long path. `sun_path` is
  /// imported as a fixed-size tuple, so it is written through a rebound pointer.
  private static func address(for path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    let bytes = Array(path.utf8)
    guard bytes.count < capacity else { throw SocketError.pathTooLong }
    withUnsafeMutablePointer(to: &addr.sun_path) { tuple in
      tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
        for (index, byte) in bytes.enumerated() { dst[index] = CChar(bitPattern: byte) }
        dst[bytes.count] = 0
      }
    }
    return addr
  }
}
