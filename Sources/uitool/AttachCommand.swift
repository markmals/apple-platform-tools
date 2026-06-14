import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.attach
/// `uitool attach <pid|bundle-id>` — make an **already-running** target inspectable
/// **without restarting it**: acquire its task port and remote-`dlopen` the boot
/// dylib, preserving the app's live on-screen state (the cooperative
/// attach-to-running path, [[domain.uitool.injection]]). Idempotent — re-attaching a
/// served target reuses the session. To start a target fresh (or a cold app), use
/// `uitool launch`.
struct Attach: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "attach",
    abstract: "Inspect an already-running app, preserving its state (attach-to-running).")

  @Argument(help: "The target running process, by pid or bundle id.")
  var app: String

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  @Flag(
    name: .customLong("no-meta"), help: "Suppress the top-level sessionId for byte-stable output.")
  var noMeta = false

  func run() throws {
    do {
      let session = try Injection.attach(target: app)
      let result = SessionResult.from(session, noMeta: noMeta)
      print(pretty ? try Output.json(result) : try Output.line(result))
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}
