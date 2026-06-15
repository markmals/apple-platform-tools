import ArgumentParser

// SPEC: command.uitool.doctor
/// The `uitool` CLI root — the agent-first live-runtime inspector over `UIToolCore`.
/// `doctor` / `list-apps` are real local system reads; the read verbs
/// (`windows` / `tree` / `find` / `node`) run over a `SnapshotSource` (an offline
/// `Capture` now, the injected `UIToolServer` later); `attach` / `detach` are the
/// gated injection half. Every subcommand obeys the AgentCLI machine contract:
/// deterministic JSON on stdout, diagnostics on stderr, exit codes as the control
/// channel.
@main
struct UITool: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "uitool",
    abstract:
      "Inspect a running AppKit/UIKit app's view tree and object graph as deterministic JSON.",
    subcommands: [
      Doctor.self, ListApps.self, Windows.self, Tree.self, Find.self, Node.self, Inspect.self,
      SchemaCommand.self, Launch.self, Attach.self, Detach.self,
    ]
  )
}
