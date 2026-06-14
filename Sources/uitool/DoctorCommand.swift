import AgentCLI
import ArgumentParser
import Foundation
import Subprocess
import UIToolCore

// SPEC: command.uitool.doctor
/// `uitool doctor` — verify the injection precondition stack with pure local reads,
/// before any injection or socket. It captures the output of `csrutil status`,
/// `nvram boot-args`, `uname -m`, `sw_vers`, the library-validation plist, and the
/// two injectable-presence stats, then hands those *results* to the pure
/// `UIToolCore.Doctor.report` interpreter and emits the two-posture verdict as
/// deterministic JSON. Every spawn is fenced: a read that fails yields a `nil`
/// input — that check becomes `unknown` and its posture reads not-usable, never a
/// crash.
///
/// The exit code follows the **cooperative** posture (inspecting apps you build and
/// sign for development): exit 0 when that common case is usable, otherwise 6. The
/// machine-wide defang is required *only* for the unrestricted posture (system /
/// notarized targets), so a stock SIP-enabled Mac is not "not ready" — it is
/// cooperative-ready the moment the arm64 boot dylib exists.
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
      injectableArm64: Doctor.Probe.injectableArm64Present(),
      injectableArm64e: Doctor.Probe.injectableArm64ePresent())
    try Output.emit(report)
    // The report is the stdout payload; the exit code follows the COOPERATIVE
    // posture — the common case (your own get-task-allow apps) — not the defanged
    // one. Exit 6 (PRECONDITION_FAILED) when that path is not usable. Today it is
    // exit 6 only because the arm64 boot dylib is the deferred injection half, NOT
    // because the machine needs a SIP/AMFI/library-validation defang.
    guard report.cooperative.usable else {
      let unmet =
        report.cooperative.requires
        .filter { $0.status != .ok }
        .map(\.name)
        .joined(separator: ", ")
      Diagnostics.fail(
        UIToolError.preconditionFailed("cooperative injection not usable — \(unmet)"))
    }
  }
}

extension Doctor {
  /// The non-Subprocess precondition reads — the library-validation plist and the
  /// two injectable-presence stats — kept off the command struct so `run()` stays a
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

    /// Whether the `UIToolBoot` injectable is on disk for the cooperative path. Now
    /// that the boot dylib is built, this checks the dev location (next to `uitool`,
    /// or `UITOOL_BOOT_DYLIB`) — so a stock Mac with the dylib built reports
    /// cooperative-ready. (The dev build is the host-arch slice; a distinct arm64
    /// slice for inspecting external arm64 apps is a packaging concern.)
    static func injectableArm64Present() -> Bool {
      BootDylib.resolvedPath() != nil
    }

    /// Whether the arm64e `UIToolBoot` injectable (the unrestricted-path slice that
    /// matches the arm64e system frameworks) is on disk. The unrestricted slice is a
    /// separate build concern from the cooperative dev dylib, so it stays `false`
    /// until that build lands — never `nil`, the disk read itself does not fail.
    static func injectableArm64ePresent() -> Bool {
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
