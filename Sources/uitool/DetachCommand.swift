import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.detach
/// `uitool detach <app>` — end an inspection session. The surface (the `<app>`
/// target, `--pretty`, `--no-meta`) parses as the spec defines, but tearing down a
/// live session means talking to the injected `UIToolServer` over its socket —
/// part of the deferred injection half that is not yet built. With no session to
/// close, `run()` fails cleanly with `NOT_ATTACHED` (exit 4): there is no live
/// bridge to tear down. Honest about the gate, never a faked "closed" result.
///
/// (The spec's steady-state `detach` is idempotent — detaching an unattached
/// target is exit 0. That idempotent success requires the session registry the
/// injection half owns; until it exists, `detach` cannot distinguish
/// already-detached from never-attachable, so it reports the honest
/// `NOT_ATTACHED` gate rather than a fabricated success.)
struct Detach: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "detach",
    abstract: "End an inspection session (gated: the injection half is not yet built).")

  @Argument(help: "The target, by pid or bundle id, as passed to attach.")
  var app: String

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  @Flag(
    name: .customLong("no-meta"), help: "Suppress the top-level sessionId for byte-stable output.")
  var noMeta = false

  func run() throws {
    Diagnostics.fail(UIToolError.notAttached)
  }
}
