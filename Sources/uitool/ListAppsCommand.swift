import AgentCLI
import AppKit
import ArgumentParser

// SPEC: command.uitool.list-apps
/// `uitool list-apps` — enumerate the GUI applications a session could attach to.
/// A pure-local read: it lists `NSWorkspace.shared.runningApplications` (the
/// regular-activation-policy apps — the ones with a Dock presence and a window
/// server connection), annotates each with pid / bundle id / name / active, and
/// emits them as a deterministic JSON-Lines stream. It opens no socket and
/// contacts no target, so it is risk-free and answers before any IPC envelope
/// exists.
///
/// (deviates: this build emits the spec's `{ "apps": [...] }` as a JSON-Lines
/// stream — one record per line — to match the house streaming idiom and the
/// pre-IPC verbs' shape; the `hardened` / `arch` code-signing facets the spec
/// lists are deferred with the injection-half attach-path work, so the record is
/// `{ active, bundleId, name, pid }`. The deterministic-order contract is kept and
/// tightened: bundleId ascending, then name, then pid — pid is never the primary
/// key.)
struct ListApps: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list-apps",
    abstract: "List the running GUI apps a session could attach to, as JSON-Lines.")

  func run() throws {
    let records = ListApps.records(from: NSWorkspace.shared.runningApplications)
    try Output.emitLines(records)
  }
}

extension ListApps {
  /// One attachable app's record — the agent reads its target off this.
  struct AppRecord: Encodable {
    let pid: Int32
    let bundleId: String?
    let name: String?
    let active: Bool
  }

  /// Project the regular-activation-policy apps into deterministically ordered
  /// records. Background/system processes (`.accessory` / `.prohibited`) are
  /// excluded — they have no window tree to inspect. Order is bundleId ascending,
  /// then name, then pid, so the stream is stable across runs (pid is never the
  /// primary key — it is non-deterministic).
  static func records(from apps: [NSRunningApplication]) -> [AppRecord] {
    apps
      .filter { $0.activationPolicy == .regular }
      .map {
        AppRecord(
          pid: $0.processIdentifier,
          bundleId: $0.bundleIdentifier,
          name: $0.localizedName,
          active: $0.isActive)
      }
      .sorted(by: appOrder)
  }

  /// The deterministic ordering: bundleId ascending (nil sorts last), then name,
  /// then pid as the final tiebreaker.
  private static func appOrder(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
    let left = (lhs.bundleId ?? "\u{10FFFF}", lhs.name ?? "", lhs.pid)
    let right = (rhs.bundleId ?? "\u{10FFFF}", rhs.name ?? "", rhs.pid)
    return left < right
  }
}
