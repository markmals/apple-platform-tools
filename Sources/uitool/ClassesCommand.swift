import AgentCLI
import ArgumentParser
import UIToolCore
import UIToolIPC

// SPEC: command.uitool.classes
/// `uitool classes <app>` — browse the target's loaded classes: `--match <regex>`
/// lists matching class names (capped), `--class <name>` reflects one class's
/// declared shape ([[command.uitool.classes]]). Class reflection is metadata only —
/// no instance, no values, no target code. Exactly one mode is required.
struct ClassesCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "classes",
    abstract: "List the target's loaded classes (--match) or reflect one (--class).")

  @Argument(help: "The attached target, by pid or bundle id.")
  var app: String

  @Option(name: .customLong("match"), help: "List loaded class names matching this regex.")
  var match: String?

  @Option(name: .customLong("class"), help: "Reflect one class's declared shape.")
  var className: String?

  @Option(name: .customLong("limit"), help: "Cap the listed names (list mode).")
  var limit: Int = 200

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  @Flag(name: .customLong("no-meta"), help: "Suppress session metadata for byte-stable output.")
  var noMeta = false

  func run() throws {
    do {
      let client = try IPCClient.connect(socketPath: try SessionSnapshotSource.socketPath(for: app))
      defer { client.close() }
      try client.handshake()

      if let className {
        emit(try client.classInfo(className: className))
      } else if let match {
        guard (try? Regex(match)) != nil else {
          throw UIToolError.badSelector("invalid --match regex: \(match)")
        }
        emit(try client.classList(pattern: match, limit: limit))
      } else {
        throw UIToolError.badSelector("classes requires --match <regex> or --class <name>")
      }
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }

  private func emit<T: Encodable>(_ value: T) {
    // Encoding a fixed result shape never fails; surface any error as a usage exit.
    do { print(pretty ? try Output.json(value) : try Output.line(value)) } catch {
      Diagnostics.fail(UIToolError.badSelector("could not encode result"))
    }
  }
}
