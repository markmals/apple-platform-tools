import AgentCLI
import ArgumentParser
import RedumpCore

// SPEC: command.redump.exports
struct Exports: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Exported symbols read natively from the Mach-O export trie.")

  @Argument(help: "Path to a Mach-O binary (thin or universal).") var binary: String

  func run() throws {
    try Output.emit(BinaryInspector.exports(path: binary))
  }
}
