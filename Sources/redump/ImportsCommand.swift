import AgentCLI
import ArgumentParser
import RedumpCore

// SPEC: command.redump.imports
struct Imports: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Imported (undefined) symbols and their source dylibs, read natively from the Mach-O."
  )

  @Argument(help: "Path to a Mach-O binary (thin or universal).") var binary: String

  @Option(help: "Keep only imports from a library whose path contains this substring.")
  var library: String?

  func run() throws {
    try Output.emit(BinaryInspector.imports(path: binary, library: library))
  }
}
