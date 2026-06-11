import AgentCLI
import ArgumentParser
import RedumpCore

// SPEC: command.redump.strings
struct Strings: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract:
      "C strings from the Mach-O's __TEXT,__cstring section, read natively from the binary.")

  @Argument(help: "Path to a Mach-O binary (thin or universal).") var binary: String

  @Option(name: .customLong("min-length"), help: "Skip strings shorter than this (in characters).")
  var minLength: Int = 4

  @Option(help: "Keep only strings whose value matches this regular expression.")
  var filter: String?

  func run() throws {
    try Output.emit(
      BinaryInspector.strings(path: binary, minLength: minLength, filter: filter))
  }
}
