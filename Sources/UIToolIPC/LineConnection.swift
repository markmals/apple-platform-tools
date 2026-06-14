import Darwin
import Foundation

// SPEC: domain.uitool.ipc
/// Newline-framed JSON-Lines I/O over a socket fd: one request or response object
/// per line ([[domain.uitool.ipc]]). Owns no socket lifecycle beyond read/write —
/// the caller closes the fd. Not thread-safe; one connection is served by one
/// thread at a time.
public final class LineConnection {
  public let fd: Int32
  private var buffer = Data()

  public init(fd: Int32) { self.fd = fd }

  /// Read one newline-terminated line (without the trailing newline), or `nil` on
  /// EOF / a closed connection.
  public func readLine() -> Data? {
    while true {
      if let newline = buffer.firstIndex(of: 0x0A) {
        let line = Data(buffer[buffer.startIndex..<newline])
        buffer.removeSubrange(buffer.startIndex...newline)
        return line
      }
      var chunk = [UInt8](repeating: 0, count: 4096)
      let count = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
      guard count > 0 else { return nil }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  /// Write one line, appending the framing newline; loops over partial writes.
  public func write(line: String) throws {
    var data = Data(line.utf8)
    data.append(0x0A)
    try data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < raw.count {
        let written = Darwin.write(fd, base + offset, raw.count - offset)
        guard written > 0 else { throw WriteError.failed }
        offset += written
      }
    }
  }

  public enum WriteError: Error { case failed }
}
