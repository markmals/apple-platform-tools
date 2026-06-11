import AgentCLI
import ArgumentParser
import RedumpCore

// SPEC: command.redump.symbols
struct Symbols: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Symbol table entries read natively from the Mach-O — no disassembler.")

  @Argument(help: "Path to a Mach-O binary (thin or universal).") var binary: String

  @Option(help: "Regex (NSRegularExpression) kept against each symbol name.")
  var filter: String?

  @Option(help: "Narrow by classification: function, data, or all (default).")
  var type: String?

  func run() throws {
    try Output.emit(BinaryInspector.symbols(path: binary, filter: filter, type: type))
  }
}
