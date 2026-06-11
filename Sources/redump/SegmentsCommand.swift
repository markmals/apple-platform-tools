import AgentCLI
import ArgumentParser
import RedumpCore

// SPEC: command.redump.segments
struct Segments: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Mach-O segments (name + virtual-address range) read natively from the binary.")

  @Argument(help: "Path to a Mach-O binary (thin or universal).") var binary: String

  func run() throws {
    try Output.emit(BinaryInspector.segments(path: binary))
  }
}
