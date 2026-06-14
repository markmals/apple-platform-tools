import AgentCLI
import AppKit
import Foundation
import TestSupport
import Testing
import UIToolCore

@testable import uitool

// SPEC: command.uitool.doctor
//
// The support-verb oracle for the uitool CLI: doctor's pure interpreter
// (`Doctor.report`) turns captured command outputs into the verdict; list-apps
// projects NSWorkspace into deterministically ordered JSON-Lines records; and the
// gated attach/detach verbs surface NOT_ATTACHED (exit 4) honestly. The pure
// Doctor.report assertions live in UIToolCoreTests/DoctorTests (the binding
// portable suite); this suite covers the CLI-edge surface — the gate error
// mapping, the list-apps projection + ordering, and an end-to-end subprocess
// smoke that the gated verbs exit non-zero with the right code.

// MARK: - doctor (CLI-edge view of the pure verdict)

@Suite(.spec("command.uitool.doctor"))
struct DoctorEdgeTests {
  @Test(.scenario("scenario.uitool.doctor-preconditions.all-pass"))
  func `a fully defanged machine's captured outputs make both postures usable`() {
    let report = UIToolCore.Doctor.report(
      csrutil: "System Integrity Protection status: disabled.",
      nvramBootArgs: "amfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
      arch: "arm64e",
      osBuild: "26D5044f",
      libraryValidation: true,
      injectableArm64: true,
      injectableArm64e: true)
    #expect(report.cooperative.usable)
    #expect(report.unrestricted.usable)
  }

  @Test
  func `a stock SIP-on machine with the arm64 injectable is cooperative-usable, not unrestricted`()
  {
    // The exit code the CLI maps follows the cooperative posture, which on a stock
    // SIP-enabled Mac is usable the moment the arm64 boot dylib exists — no defang.
    let report = UIToolCore.Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "",
      arch: "arm64",
      osBuild: "26D5044f",
      libraryValidation: false,
      injectableArm64: true,
      injectableArm64e: false)
    #expect(report.cooperative.usable)
    #expect(!report.unrestricted.usable)
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.one-fail"))
  func `SIP enabled makes the unrestricted posture unusable with the sip check failed`() {
    let report = UIToolCore.Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "amfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
      arch: "arm64e",
      osBuild: "26D5044f",
      libraryValidation: true,
      injectableArm64: true,
      injectableArm64e: true)
    #expect(!report.unrestricted.usable)
    #expect(report.unrestricted.requires.first { $0.name == "sip" }?.status == .failed)
  }

  @Test
  func `both injectable probes are honestly absent until the injection half lands`() {
    // The injection half is not built, so both on-disk probes report false (present-
    // and-readable but absent), never nil — the disk read itself never fails.
    #expect(Doctor.Probe.injectableArm64Present() == false)
    #expect(Doctor.Probe.injectableArm64ePresent() == false)
  }
}

// MARK: - list-apps (deterministic projection + ordering)

@Suite(.spec("command.uitool.list-apps"))
struct ListAppsTests {
  @Test
  func `list-apps runs over NSWorkspace and emits valid JSON-Lines`() throws {
    // A light smoke test: list-apps touches the live NSWorkspace, so assert only
    // that it produces records that round-trip as JSON-Lines (one object per line),
    // not a specific app set.
    let records = ListApps.records(from: NSWorkspace.shared.runningApplications)
    for record in records {
      let line = try Output.line(record)
      #expect(!line.contains("\n"))
      let object =
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
      #expect(object != nil)
      #expect(object?["pid"] != nil)
      #expect(object?.keys.contains("active") == true)
    }
  }

  @Test
  func `records are ordered by bundleId then name then pid`() throws {
    // Projection ordering is deterministic and independent of the input order, so
    // build synthetic NSRunningApplication-free records is impossible (the type is
    // opaque) — instead assert the order over the live set is sorted by the
    // contract key, which holds regardless of which apps are running.
    let records = ListApps.records(from: NSWorkspace.shared.runningApplications)
    let keys = records.map { ($0.bundleId ?? "\u{10FFFF}", $0.name ?? "", $0.pid) }
    let sorted = keys.sorted { $0 < $1 }
    #expect(keys.elementsEqual(sorted) { $0 == $1 })
  }
}

// MARK: - attach / launch / detach surfaces

@Suite(.spec("command.uitool.attach"))
struct AttachGateTests {
  @Test
  func `the attach surface parses its target and flags`() throws {
    let attach = try Attach.parse(["com.apple.mail", "--no-meta", "--pretty"])
    #expect(attach.app == "com.apple.mail")
    #expect(attach.noMeta)
    #expect(attach.pretty)
  }

  @Test
  func `the launch surface parses its target, replace, and passthrough args`() throws {
    let launch = try Launch.parse(["com.example.App", "--replace", "--", "--flag", "value"])
    #expect(launch.app == "com.example.App")
    #expect(launch.replace)
    #expect(launch.appArgs == ["--flag", "value"])
  }

  @Test
  func `the detach surface parses its target and flags`() throws {
    let detach = try Detach.parse(["4821", "--pretty"])
    #expect(detach.app == "4821")
    #expect(detach.pretty)
  }

  @Test
  func `the gate maps to NOT_ATTACHED at exit 4`() {
    // attach/detach both fail via Diagnostics.fail(UIToolError.notAttached), which
    // exits the process; the in-process assertion is that the error it gates on is
    // the closed NOT_ATTACHED code at exit 4 — the honest "injection half not yet
    // built" signal, never a faked session.
    #expect(UIToolError.notAttached.code == "NOT_ATTACHED")
    #expect(UIToolError.notAttached.exitCode == 4)
  }

  @Test
  func `the built uitool binary gates reads and resolves launch errors`() throws {
    guard let binary = builtUIToolBinary() else { return }

    // A read against a pid with no live session refuses with NOT_ATTACHED (exit 4)
    // — the socket simply isn't there to connect to.
    let (readStatus, readErr) = try runUITool(binary, ["windows", "999999"])
    #expect(readStatus == 4)
    #expect(readErr.contains("NOT_ATTACHED"))

    // detach is idempotent: nothing is attached at that pid, so it is a clean no-op.
    let (detachStatus, _) = try runUITool(binary, ["detach", "999999"])
    #expect(detachStatus == 0)

    // launch with no resolvable app is APP_NOT_FOUND (exit 3), raised before any
    // dylib lookup or spawn.
    let (launchStatus, launchErr) = try runUITool(binary, ["launch", "/no/such/app.app"])
    #expect(launchStatus == 3)
    #expect(launchErr.contains("APP_NOT_FOUND"))
  }
}

// MARK: - subprocess smoke harness

/// The built `uitool` product, if SwiftPM put it next to the test bundle; `nil`
/// otherwise so the end-to-end smoke skips cleanly rather than failing on a layout
/// it cannot control.
private func builtUIToolBinary() -> URL? {
  let bundle = Bundle(for: BundleAnchor.self)
  let dir = bundle.bundleURL.deletingLastPathComponent()
  let candidate = dir.appendingPathComponent("uitool")
  return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
}

private final class BundleAnchor {}

/// Run the built CLI and return its exit code plus captured stderr. The payload
/// contract: stderr carries the diagnostic, exit code carries the control signal.
private func runUITool(_ binary: URL, _ arguments: [String]) throws -> (Int32, String) {
  let process = Process()
  process.executableURL = binary
  process.arguments = arguments
  let errPipe = Pipe()
  process.standardError = errPipe
  process.standardOutput = Pipe()
  try process.run()
  process.waitUntilExit()
  let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
  return (process.terminationStatus, String(decoding: errData, as: UTF8.self))
}
