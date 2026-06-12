import AgentCLI
import ArgumentParser
import UIToolCore

// SPEC: command.uitool.windows
/// `uitool windows <app>` — list the app's top-level windows as window-root records
/// in `NSApp.windows` order. The cheapest query in the surface: a fixed, tiny
/// payload with no descendant walk and no `--fields`/`--include` (the record shape
/// is fixed). Resolves a `SnapshotSource`, indexes a `NodeTree`, and streams
/// `Verbs.windows` plus the trailing IPC envelope. An empty window set is a valid
/// empty result (exit 0, `totalMatched: 0`), never a failure.
struct Windows: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "windows",
    abstract: "List the target app's top-level windows as window-root records.")

  @Argument(help: "The attached target — pid or bundle id. Omit when reading --snapshot.")
  var app: String?

  @Option(name: .customLong("snapshot"), help: "Read a captured Capture JSON instead of attaching.")
  var snapshot: String?

  @Flag(name: .customLong("no-meta"), help: "Suppress sessionId and _meta for byte-stable output.")
  var noMeta = false

  func run() throws {
    do {
      let resolved = try loadTree(snapshot: snapshot, app: app)
      let result = try Verbs.windows(resolved.tree)
      try runStream(result, sessionId: resolved.sessionId, noMeta: noMeta)
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}
