import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.schema
/// `uitool schema` — print the tool's output contract (the record fields + the
/// exit-code map) as deterministic JSON. Static and offline: no target, no node, no
/// injection ([[command.uitool.schema]]). The cheapest verb — the agent reads the
/// contract from the tool instead of out-of-band docs.
struct SchemaCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "schema",
    abstract: "Print the output contract (record fields + exit codes) as JSON.")

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  func run() throws {
    let contract = SchemaCatalog.contract()
    print(pretty ? try Output.json(contract) : try Output.line(contract))
  }
}
