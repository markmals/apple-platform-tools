import AgentCLI
import ArgumentParser
import Foundation
import Subprocess
import UIToolCore

// SPEC: command.uitool.doctor
/// `uitool doctor` — verify the injection precondition stack with pure local reads,
/// before any injection or socket. It captures the output of `csrutil status`,
/// `nvram boot-args`, `uname -m`, `sw_vers`, the library-validation plist, and the
/// injectable-presence stat, then hands those *results* to the pure
/// `UIToolCore.Doctor.report` interpreter and emits the verdict as deterministic
/// JSON. Every spawn is fenced: a read that fails yields a `nil` input — that
/// check becomes `unknown` and the machine reads not-ready, never a crash.
///
/// `--fix` (sudo auto-remediation of the boot-arg / library-validation checks) is
/// part of the gated injection half and is **not** wired here: this build detects
/// and instructs only, per the spec's detect-by-default posture.
struct Doctor: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Verify the SIP/AMFI/library-validation/arm64e/arch precondition stack.")

  func run() async throws {
    let report = UIToolCore.Doctor.report(
      csrutil: await capture(.name("csrutil"), ["status"]),
      // An unset `boot-args` is the enforcing state, not an unreadable one: `nvram`
      // exits non-zero but ran, so keep its empty output (→ amfi/arm64e `failed`
      // with a remedy) rather than collapsing it to nil (→ `unknown`, no remedy).
      nvramBootArgs: await capture(.name("nvram"), ["boot-args"], allowNonZeroExit: true),
      arch: await capture(.name("uname"), ["-m"]),
      osBuild: await capture(.name("sw_vers"), ["-buildVersion"]),
      libraryValidation: Doctor.Probe.libraryValidationDisabled(),
      uitoolBuilt: Doctor.Probe.injectablePresent())
    try Output.emit(report)
    // The report is the stdout payload; the exit code is the branchable verdict —
    // exit 6 (PRECONDITION_FAILED) when the machine is not injection-ready.
    guard report.ready else {
      let unmet = report.checks.filter { $0.status != .ok }.map(\.name).joined(separator: ", ")
      Diagnostics.fail(UIToolError.preconditionFailed("machine not injection-ready — \(unmet)"))
    }
  }
}

extension Doctor {
  /// The two non-Subprocess precondition reads — the library-validation plist and
  /// the injectable-presence stat — kept off the command struct so `run()` stays a
  /// thin spawn-and-emit edge. The four command reads go through `capture`; the
  /// pure interpretation is `UIToolCore.Doctor.report`.
  enum Probe {
    /// Whether library validation is disabled, read from the security plist. `nil`
    /// when the plist cannot be read — the check then reads `unknown`, not `failed`.
    static func libraryValidationDisabled() -> Bool? {
      let path =
        "/Library/Preferences/com.apple.security.libraryvalidation.plist"
      guard let dict = NSDictionary(contentsOfFile: path) else { return nil }
      return dict["DisableLibraryValidation"] as? Bool
    }

    /// Whether the arm64e `UIToolBoot` injectable is on disk. The injection half is
    /// not yet built, so this is honestly `false` here (present-and-readable but
    /// absent), never `nil` — the disk read itself does not fail.
    static func injectablePresent() -> Bool {
      false
    }
  }
}

// SPEC: command.uitool.doctor
/// Run a local read and return its trimmed stdout, or `nil` on any failure (spawn
/// error, non-zero exit). A `nil` is the signal the pure interpreter turns into an
/// `unknown` check — a missing or unreadable tool must never crash `doctor`.
private func capture(
  _ executable: Subprocess.Executable, _ arguments: [String], allowNonZeroExit: Bool = false
) async -> String? {
  do {
    let result = try await Subprocess.run(
      executable,
      arguments: Arguments(arguments),
      output: .string(limit: 64 * 1024),
      error: .discarded)
    // `allowNonZeroExit` keeps the (possibly empty) stdout of a tool that *ran* but
    // exited non-zero — e.g. `nvram boot-args` on an unset variable, a known state,
    // not an unreadable one. Without it, a non-zero exit is `nil` ("couldn't read").
    var ranOK = false
    if case .exited(0) = result.terminationStatus { ranOK = true }
    guard allowNonZeroExit || ranOK else { return nil }
    return (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  } catch {
    return nil
  }
}
