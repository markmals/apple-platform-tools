import Foundation

// SPEC: domain.agent-cli
/// The exit-code taxonomy shared across tools. `0` is success; `2` is a usage
/// error (matching ArgumentParser's validation exit). Tools extend the space
/// above `2` with their own `AgentError` values. A zero-result query is success,
/// never failure.
public enum ExitStatus {
  public static let success: Int32 = 0
  public static let usage: Int32 = 2
}

// SPEC: domain.agent-cli
/// A failure a tool surfaces with a precise exit code and a human-readable
/// message. The message goes to stderr; the code is the control channel.
public protocol AgentError: Error {
  var exitCode: Int32 { get }
  var message: String { get }
}

// SPEC: domain.agent-cli
/// stderr carries diagnostics; stdout carries the machine payload alone.
public enum Diagnostics {
  /// Write a diagnostic line to stderr. Never touches stdout.
  public static func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }

  /// Write an error's message to stderr and exit with its code. Call this at the
  /// top of a command's catch so the stdout payload contract stays clean on failure.
  public static func fail(_ error: some AgentError) -> Never {
    warn(error.message)
    exit(error.exitCode)
  }

  /// Write a message to stderr and exit with an explicit code.
  public static func fail(_ message: String, code: Int32) -> Never {
    warn(message)
    exit(code)
  }
}
