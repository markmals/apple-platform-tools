import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.attach
/// `uitool attach <app>` — make a target inspectable. The command surface (the
/// `<app>` target, `--relaunch`, `--pretty`, `--no-meta`) parses exactly as the
/// spec defines, so the agent-facing contract is real today. The action is
/// **gated**: injecting `UIToolServer` into the target over the per-pid socket is
/// the deferred injection half (`UIToolServer` / `UIToolBoot`), which is not yet
/// built — so `run()` fails cleanly with `NOT_ATTACHED` (exit 4) rather than
/// faking a session or crashing. The socket can never open, which is exactly the
/// exit-4 "injection failed" state the spec defines; an honest gate, not a stub
/// that pretends.
struct Attach: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "attach",
    abstract: "Inject the inspector into a target app (gated: the injection half is not yet built)."
  )

  @Argument(help: "The target process, by pid or bundle id.")
  var app: String

  @Flag(
    name: .customLong("relaunch"),
    help: "Use the relaunch-inject path (Path A) instead of running-attach.")
  var relaunch = false

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  @Flag(
    name: .customLong("no-meta"), help: "Suppress the top-level sessionId for byte-stable output.")
  var noMeta = false

  func run() throws {
    Diagnostics.fail(UIToolError.notAttached)
  }
}
