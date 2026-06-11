import AgentCLI
import ArgumentParser
import RedumpCore

@main
struct Redump: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "redump",
    abstract:
      "Reverse-engineering binary inspection. Native Mach-O reads now; IDA/Hopper-backed disassembly is a gated, later slice.",
    subcommands: [
      Info.self, Segments.self, Symbols.self, Imports.self, Exports.self, Strings.self,
      Backends.self,
    ]
  )
}

// SPEC: command.redump.info
struct Info: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Binary metadata (file type, architectures) read natively from the Mach-O.")

  @Argument(help: "Path to a Mach-O binary (thin or universal).") var binary: String

  func run() throws {
    try Output.emit(BinaryInspector.info(path: binary))
  }
}
