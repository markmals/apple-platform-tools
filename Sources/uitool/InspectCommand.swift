import AgentCLI
import ArgumentParser
import UIToolCore
import UIToolIPC

// SPEC: command.uitool.inspect (deviates: --fields projection over the result is deferred for v1; --match narrows the output)
/// `uitool inspect <app> --at <node-id>` — read a live object's ivar values and
/// class reflection. Ivar reads are safe (no target code runs); `--invoke` adds
/// property-getter values (gated, timed, safety-screened, [[command.uitool.inspect]]).
/// `--match` narrows ivars/properties by name. The node id is resolved server-side
/// via [[domain.uitool.registry]]; a stale handle is `STALE_NODE` (exit 5).
struct Inspect: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "inspect",
    abstract: "Read a live object's ivars, properties, and reflection.")

  @Argument(help: "The attached target, by pid or bundle id.")
  var app: String

  @Option(name: .customLong("at"), help: "The node id to inspect (e.g. 7:w0/cv/vev0).")
  var at: String

  @Flag(
    name: .customLong("invoke"),
    help: "Also invoke property getters to read their values (runs target code; gated).")
  var invoke = false

  @Option(name: .customLong("match"), help: "Narrow ivars/properties to names matching this regex.")
  var match: String?

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  @Flag(
    name: .customLong("no-meta"), help: "Suppress session metadata for byte-stable output.")
  var noMeta = false

  func run() throws {
    do {
      guard let node = NodeID(parsing: at) else {
        throw UIToolError.badSelector("invalid node id: \(at)")
      }
      if let match, (try? Regex(match)) == nil {
        throw UIToolError.badSelector("invalid --match regex: \(match)")
      }
      let client = try IPCClient.connect(socketPath: try SessionSnapshotSource.socketPath(for: app))
      defer { client.close() }
      try client.handshake()
      let result = try client.inspect(node: node, invoke: invoke, match: match)
      print(pretty ? try Output.json(result) : try Output.line(result))
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}
