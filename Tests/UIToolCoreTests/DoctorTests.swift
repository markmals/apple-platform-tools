import TestSupport
import Testing

@testable import UIToolCore

// SPEC: command.uitool.doctor
//
// The pure doctor-report oracle: `Doctor.report` interprets already-captured
// command outputs into a two-posture `DoctorReport` with no spawn, no machine
// state, no AppKit. macOS gates injection per target, so the report carries two
// postures: `cooperative` (inspect your own get-task-allow apps — SIP may stay on)
// and `unrestricted` (inspect any app incl. system — needs the full defang). Each
// case feeds defanged / hardened / today's-reality command outputs and asserts the
// per-check verdict, the frozen check ids + order per posture, the `usable`
// aggregate per posture, and the `unknown` state a `nil` (unread) input produces.
// This is the purity boundary: the interpretation is total over its inputs; the CLI
// edge that spawns the commands is tested separately.

private let kCooperativeOrder = ["arch", "injectable-arm64"]
private let kUnrestrictedOrder = [
  "sip", "amfi", "libval", "arm64e-abi", "arch", "injectable-arm64e",
]

/// A fully defanged machine with both injectables built: SIP off, both boot-args
/// set, library validation disabled, arm64e host, both arm64 and arm64e injectables
/// present. Both postures are usable here.
private func defangedReport() -> DoctorReport {
  Doctor.report(
    csrutil: "System Integrity Protection status: disabled.",
    nvramBootArgs: "boot-args\tamfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
    arch: "arm64e",
    osBuild: "26D5044f",
    libraryValidation: true,
    injectableArm64: true,
    injectableArm64e: true)
}

@Suite(.spec("command.uitool.doctor"))
struct DoctorReportTests {
  @Test(.scenario("scenario.uitool.doctor-preconditions.all-pass"))
  func `a fully defanged machine with both injectables makes both postures usable`() {
    let report = defangedReport()
    #expect(report.cooperative.usable)
    #expect(report.unrestricted.usable)
    #expect(report.cooperative.requires.map(\.name) == kCooperativeOrder)
    #expect(report.unrestricted.requires.map(\.name) == kUnrestrictedOrder)
    #expect(report.cooperative.requires.allSatisfy { $0.status == .ok })
    #expect(report.unrestricted.requires.allSatisfy { $0.status == .ok })
    #expect(report.cooperative.requires.allSatisfy { $0.remedy == nil })
    #expect(report.unrestricted.requires.allSatisfy { $0.remedy == nil })
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.cooperative-ready"))
  func
    `a stock SIP-on machine with the arm64 injectable is cooperative-usable but not unrestricted`()
  {
    // The key reframe: a stock, SIP-enabled Mac is cooperative-ready the moment the
    // arm64 boot dylib exists — no SIP/AMFI/libval defang. The unrestricted posture
    // (system / notarized targets) still needs the full machine-wide defang, which
    // this machine does not have.
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "",  // no boot-args; AMFI enforcing, arm64e-abi absent
      arch: "arm64",  // a stock Xcode app is arm64
      osBuild: "26D5044f",
      libraryValidation: false,
      injectableArm64: true,  // the cooperative boot dylib is present
      injectableArm64e: false)  // the arm64e slice is not

    #expect(report.cooperative.usable)
    #expect(!report.unrestricted.usable)
    // Cooperative requires only arch + the arm64 dylib — both met, and crucially no
    // SIP/AMFI/libval item appears in its requires set.
    #expect(report.cooperative.requires.map(\.name) == kCooperativeOrder)
    #expect(report.cooperative.requires.allSatisfy { $0.status == .ok })
    #expect(!report.cooperative.requires.contains { $0.name == "sip" })
    #expect(!report.cooperative.requires.contains { $0.name == "amfi" })
    #expect(!report.cooperative.requires.contains { $0.name == "libval" })
    // The unrestricted posture is unusable because the defang stack is unmet.
    let sip = report.unrestricted.requires.first { $0.name == "sip" }
    #expect(sip?.status == .failed)
    #expect(sip?.remedy != nil)
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.injection-half-pending"))
  func
    `today's reality with no injectable leaves cooperative requires showing only the missing dylib`()
  {
    // The injection half (UIToolBoot/UIToolServer) is not built, so neither
    // injectable is present. On a stock dev Mac the cooperative posture is then
    // unusable for exactly one reason — the missing arm64 dylib — NOT any
    // SIP/AMFI/library-validation defang. The report makes that gap legible.
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "",
      arch: "arm64",
      osBuild: "26D5044f",
      libraryValidation: false,
      injectableArm64: false,
      injectableArm64e: false)

    #expect(!report.cooperative.usable)
    // The only failing cooperative check is the injectable — arch still passes, and
    // no SIP/AMFI/libval item is even present to fail.
    let cooperativeFailures = report.cooperative.requires.filter { $0.status != .ok }
    #expect(cooperativeFailures.map(\.name) == ["injectable-arm64"])
    #expect(cooperativeFailures.first?.detail == "absent")
    #expect(cooperativeFailures.first?.remedy != nil)
    #expect(report.cooperative.requires.first { $0.name == "arch" }?.status == .ok)
    // The unrestricted posture is also unusable (defang absent + injectable absent).
    #expect(!report.unrestricted.usable)
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.one-fail"))
  func `SIP enabled fails just the sip check in the unrestricted posture with a remedy`() {
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "amfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
      arch: "arm64e",
      osBuild: "26D5044f",
      libraryValidation: true,
      injectableArm64: true,
      injectableArm64e: true)

    #expect(!report.unrestricted.usable)
    let sip = report.unrestricted.requires.first { $0.name == "sip" }
    #expect(sip?.status == .failed)
    #expect(sip?.detail == "enabled")
    #expect(sip?.remedy != nil)
    // Every other unrestricted check still passes — judged independently.
    #expect(
      report.unrestricted.requires.filter { $0.name != "sip" }.allSatisfy { $0.status == .ok })
    // Cooperative is unaffected by SIP — it never reads it.
    #expect(report.cooperative.usable)
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.multi-fail"))
  func `several unmet unrestricted preconditions each report their own remedy`() {
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "",  // neither boot-arg set
      arch: "x86_64",
      osBuild: "26D5044f",
      libraryValidation: false,
      injectableArm64: false,
      injectableArm64e: false)

    #expect(!report.unrestricted.usable)
    let failed = report.unrestricted.requires.filter { $0.status == .failed }
    // sip, amfi, libval, arm64e-abi, arch, injectable-arm64e — all six fail.
    #expect(failed.count == 6)
    #expect(failed.allSatisfy { $0.remedy != nil })
    // The failing arch check carries the concrete running arch as its detail.
    #expect(report.unrestricted.requires.first { $0.name == "arch" }?.detail == "x86_64")
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.independent"))
  func `SIP-disabled-but-AMFI-missing judges each unrestricted check independently`() {
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: disabled.",
      nvramBootArgs: "-arm64e_preview_abi",  // amfi missing, abi present
      arch: "arm64e",
      osBuild: "26D5044f",
      libraryValidation: true,
      injectableArm64: true,
      injectableArm64e: true)

    #expect(report.unrestricted.requires.first { $0.name == "sip" }?.status == .ok)
    #expect(report.unrestricted.requires.first { $0.name == "amfi" }?.status == .failed)
    #expect(report.unrestricted.requires.first { $0.name == "arm64e-abi" }?.status == .ok)
    #expect(!report.unrestricted.usable)
  }

  @Test
  func `an unread command makes its check unknown not failed and its posture not usable`() {
    // A nil input is the signal a spawn failed: the check is unknown (couldn't
    // tell), never a silent pass, and its posture reads not-usable.
    let report = Doctor.report(
      csrutil: nil,
      nvramBootArgs: "amfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
      arch: "arm64e",
      osBuild: nil,
      libraryValidation: true,
      injectableArm64: true,
      injectableArm64e: true)

    let sip = report.unrestricted.requires.first { $0.name == "sip" }
    #expect(sip?.status == .unknown)
    #expect(sip?.detail == "unread")
    #expect(sip?.remedy == nil)
    #expect(!report.unrestricted.usable)
    // The unread input was SIP, which cooperative never reads — it stays usable.
    #expect(report.cooperative.usable)
  }

  @Test
  func `each posture's requires array is always its frozen ids in fixed order`() {
    // Determinism: order is stable regardless of which checks pass or are unread.
    let report = Doctor.report(
      csrutil: nil, nvramBootArgs: nil, arch: nil, osBuild: nil,
      libraryValidation: nil, injectableArm64: nil, injectableArm64e: nil)
    #expect(report.cooperative.requires.map(\.name) == kCooperativeOrder)
    #expect(report.unrestricted.requires.map(\.name) == kUnrestrictedOrder)
    #expect(report.cooperative.requires.allSatisfy { $0.status == .unknown })
    #expect(report.unrestricted.requires.allSatisfy { $0.status == .unknown })
    #expect(!report.cooperative.usable)
    #expect(!report.unrestricted.usable)
  }

  @Test
  func `empty boot-args is the enforcing state and fails amfi and arm64e, not unknown`() {
    // The CLI hands an UNSET boot-args through as "" (it ran, just exits non-zero),
    // so the missing AMFI/arm64e flags are failed-with-remedy, never an "unread" gap.
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: disabled.",
      nvramBootArgs: "",
      arch: "arm64e", osBuild: "26D5044f", libraryValidation: true,
      injectableArm64: true, injectableArm64e: true)
    let amfi = report.unrestricted.requires.first { $0.name == "amfi" }
    let abi = report.unrestricted.requires.first { $0.name == "arm64e-abi" }
    #expect(amfi?.status == .failed)
    #expect(amfi?.remedy != nil)
    #expect(abi?.status == .failed)
    #expect(!report.unrestricted.usable)
  }

  @Test
  func `the note lines describe each posture without over-claiming`() {
    let report = defangedReport()
    // Cooperative explicitly disclaims any machine defang.
    #expect(report.cooperative.note.contains("get-task-allow"))
    #expect(report.cooperative.note.contains("No SIP"))
    // Unrestricted scopes the defang to apps you did not sign.
    #expect(report.unrestricted.note.contains("did NOT sign"))
    #expect(report.unrestricted.note.contains("Recovery"))
  }

  @Test
  func `the precondition-failed error maps to PRECONDITION_FAILED and exit 6`() {
    // doctor's not-usable verdict is branchable without parsing prose.
    let error = UIToolError.preconditionFailed("injectable-arm64")
    #expect(error.code == "PRECONDITION_FAILED")
    #expect(error.exitCode == 6)
  }
}
