import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.launch
/// `uitool launch <app>` — start a target **fresh** under inspection: spawn it
/// under `DYLD_INSERT_LIBRARIES` so the boot dylib loads at launch and starts the
/// server, then handshake and report the session. The cooperative spawn-inject path
/// ([[domain.uitool.injection]]) — no machine defang, no debugger entitlement. For
/// a clean launch state or a cold app; to inspect an already-running app preserving
/// its state, use `uitool attach`.
struct Launch: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "launch",
    abstract: "Start an app fresh under inspection (spawn-inject; clean state).")

  @Argument(help: "The app to launch — a bundle id, a .app path, or an executable path.")
  var app: String

  @Flag(
    name: .customLong("replace"),
    help: "If the target is already running, terminate it first, then launch fresh.")
  var replace = false

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  @Flag(
    name: .customLong("no-meta"), help: "Suppress the top-level sessionId for byte-stable output.")
  var noMeta = false

  @Argument(
    parsing: .postTerminator, help: "Arguments passed to the launched app, after a -- terminator.")
  var appArgs: [String] = []

  func run() throws {
    do {
      let session = try Injection.launch(target: app, replace: replace, args: appArgs)
      let result = SessionResult.from(session, noMeta: noMeta)
      print(pretty ? try Output.json(result) : try Output.line(result))
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}
