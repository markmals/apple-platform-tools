import AgentCLI
import ArgumentParser
import RedumpCore

// SPEC: command.redump.backends
struct Backends: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "backends",
    abstract:
      "Report which disassembler backends (IDA Pro / Hopper) are configured for the analysis commands."
  )

  func run() throws {
    try Output.emit(BackendDetector.detect())
  }
}
