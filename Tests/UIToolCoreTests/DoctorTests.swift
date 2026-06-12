import TestSupport
import Testing

@testable import UIToolCore

// SPEC: command.uitool.doctor
//
// The pure doctor-report oracle: `Doctor.report` interprets already-captured
// command outputs into a `DoctorReport` with no spawn, no machine state, no
// AppKit. Each case feeds defanged / hardened command outputs and asserts the
// per-check verdict, the frozen check ids + order, the `ready` aggregate, and the
// `unknown` state a `nil` (unread) input produces. This is the purity boundary:
// the interpretation is total over its inputs; the CLI edge that spawns the
// commands is tested separately.

private let kCheckOrder = ["sip", "amfi", "libval", "arm64e-abi", "arch", "uitool-built"]

/// A machine where every precondition is met (SIP off, both boot-args set, library
/// validation disabled, arm64e host, injectable present).
private func defangedReport() -> DoctorReport {
  Doctor.report(
    csrutil: "System Integrity Protection status: disabled.",
    nvramBootArgs: "boot-args\tamfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
    arch: "arm64e",
    osBuild: "26D5044f",
    libraryValidation: true,
    uitoolBuilt: true)
}

@Suite(.spec("command.uitool.doctor"))
struct DoctorReportTests {
  @Test(.scenario("scenario.uitool.doctor-preconditions.all-pass"))
  func `a fully configured machine reports ready with every check ok`() {
    let report = defangedReport()
    #expect(report.ready)
    #expect(report.checks.map(\.name) == kCheckOrder)
    #expect(report.checks.allSatisfy { $0.status == .ok })
    #expect(report.checks.allSatisfy { $0.remedy == nil })
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.one-fail"))
  func `SIP enabled fails just the sip check with a remedy and not-ready`() {
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "amfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
      arch: "arm64e",
      osBuild: "26D5044f",
      libraryValidation: true,
      uitoolBuilt: true)

    #expect(!report.ready)
    let sip = report.checks.first { $0.name == "sip" }
    #expect(sip?.status == .failed)
    #expect(sip?.detail == "enabled")
    #expect(sip?.remedy != nil)
    // Every other check still passes — judged independently, not suppressed.
    #expect(report.checks.filter { $0.name != "sip" }.allSatisfy { $0.status == .ok })
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.multi-fail"))
  func `several unmet preconditions each report their own remedy`() {
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: enabled.",
      nvramBootArgs: "",  // neither boot-arg set
      arch: "x86_64",
      osBuild: "26D5044f",
      libraryValidation: false,
      uitoolBuilt: false)

    #expect(!report.ready)
    let failed = report.checks.filter { $0.status == .failed }
    #expect(failed.count == 6)
    #expect(failed.allSatisfy { $0.remedy != nil })
    // The failing arch check carries the concrete running arch as its detail.
    #expect(report.checks.first { $0.name == "arch" }?.detail == "x86_64")
  }

  @Test(.scenario("scenario.uitool.doctor-preconditions.independent"))
  func `SIP-disabled-but-AMFI-missing judges each check independently`() {
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: disabled.",
      nvramBootArgs: "-arm64e_preview_abi",  // amfi missing, abi present
      arch: "arm64e",
      osBuild: "26D5044f",
      libraryValidation: true,
      uitoolBuilt: true)

    #expect(report.checks.first { $0.name == "sip" }?.status == .ok)
    #expect(report.checks.first { $0.name == "amfi" }?.status == .failed)
    #expect(report.checks.first { $0.name == "arm64e-abi" }?.status == .ok)
    #expect(!report.ready)
  }

  @Test
  func `an unread command makes its check unknown not failed and not-ready`() {
    // A nil input is the signal a spawn failed: the check is unknown (couldn't
    // tell), never a silent pass, and the machine reads not-ready.
    let report = Doctor.report(
      csrutil: nil,
      nvramBootArgs: "amfi_get_out_of_my_way=0x1 -arm64e_preview_abi",
      arch: "arm64e",
      osBuild: nil,
      libraryValidation: true,
      uitoolBuilt: true)

    let sip = report.checks.first { $0.name == "sip" }
    #expect(sip?.status == .unknown)
    #expect(sip?.detail == "unread")
    #expect(sip?.remedy == nil)
    #expect(!report.ready)
  }

  @Test
  func `the checks array is always the six frozen ids in fixed order`() {
    // Determinism: order is stable regardless of which checks pass or are unread.
    let report = Doctor.report(
      csrutil: nil, nvramBootArgs: nil, arch: nil, osBuild: nil,
      libraryValidation: nil, uitoolBuilt: nil)
    #expect(report.checks.map(\.name) == kCheckOrder)
    #expect(report.checks.allSatisfy { $0.status == .unknown })
    #expect(!report.ready)
  }

  @Test
  func `empty boot-args is the enforcing state and fails amfi and arm64e, not unknown`() {
    // The CLI hands an UNSET boot-args through as "" (it ran, just exits non-zero),
    // so the missing AMFI/arm64e flags are failed-with-remedy, never an "unread" gap.
    let report = Doctor.report(
      csrutil: "System Integrity Protection status: disabled.",
      nvramBootArgs: "",
      arch: "arm64e", osBuild: "26D5044f", libraryValidation: true, uitoolBuilt: true)
    let amfi = report.checks.first { $0.name == "amfi" }
    let abi = report.checks.first { $0.name == "arm64e-abi" }
    #expect(amfi?.status == .failed)
    #expect(amfi?.remedy != nil)
    #expect(abi?.status == .failed)
    #expect(!report.ready)
  }

  @Test
  func `the precondition-failed error maps to PRECONDITION_FAILED and exit 6`() {
    // doctor's not-ready verdict is branchable without parsing prose.
    let error = UIToolError.preconditionFailed("amfi, arm64e-abi")
    #expect(error.code == "PRECONDITION_FAILED")
    #expect(error.exitCode == 6)
  }
}
