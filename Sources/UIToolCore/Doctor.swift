import Foundation

// SPEC: command.uitool.doctor
/// One precondition's verdict. `name` is the frozen check id from
/// [[command.uitool.doctor]] (`sip` / `amfi` / `libval` / `arm64e-abi` / `arch` /
/// `uitool-built`); `detail` is the spec's byte-stable token, never free prose;
/// `remedy` is the one-line fix, present only on a failed check.
///
/// `status` carries one extra state the spec's `pass: Bool` cannot: `unknown`,
/// for a check whose underlying command could not be read (the spawn failed). A
/// spawn failure must never crash `doctor` and must not masquerade as a pass — it
/// is an honest "couldn't tell", and an `unknown` check leaves the machine
/// not-ready just like a failure does.
public struct PreconditionCheck: Codable, Equatable, Sendable {
  /// The frozen check id (`sip`, `amfi`, `libval`, `arm64e-abi`, `arch`, `uitool-built`).
  public let name: String
  /// `ok` (pass), `failed` (read and unmet), or `unknown` (its input could not be read).
  public let status: Status
  /// The byte-stable token for this check's verdict (e.g. `disabled` / `enforcing`).
  public let detail: String
  /// The one-line remedy — present only on a `failed` check, never on `ok`/`unknown`.
  public let remedy: String?

  public enum Status: String, Codable, Sendable {
    case ok
    case failed
    case unknown
  }

  public init(name: String, status: Status, detail: String, remedy: String? = nil) {
    self.name = name
    self.status = status
    self.detail = detail
    self.remedy = remedy
  }
}

// SPEC: command.uitool.doctor
/// The aggregate verdict: the per-check array in the spec's fixed order, plus the
/// single `ready` flag the CLI maps to its exit code (0 when ready, 6 otherwise).
/// `ready` is true only when *every* check passed — a single `failed` or
/// `unknown` check leaves the machine not-ready.
public struct DoctorReport: Codable, Equatable, Sendable {
  public let checks: [PreconditionCheck]
  public let ready: Bool
  /// The OS build (e.g. `26D5044f`) — precondition validity is OS-build-specific
  /// (arm64e injection regresses across Tahoe 26.x). Machine-specific, so it is
  /// normalized out of snapshot assertions like a session id; `nil` when `sw_vers`
  /// could not be read. Not itself a check — it never affects `ready`.
  public let osBuild: String?

  public init(checks: [PreconditionCheck], osBuild: String? = nil) {
    self.checks = checks
    self.ready = checks.allSatisfy { $0.status == .ok }
    self.osBuild = osBuild
  }
}

// SPEC: command.uitool.doctor
/// The pure, total interpreter that turns already-captured command outputs into a
/// `DoctorReport`. It never spawns anything and never fails — the CLI edge runs
/// `csrutil status`, `nvram boot-args`, `uname -m`, `sw_vers`, and the
/// framework-presence stat, then hands the *results* here. A `nil` input means
/// that read could not be made (the spawn failed): the dependent check(s) become
/// `unknown` rather than crashing or silently passing.
///
/// (deviates: the spec's command JSON is `{ok, osBuild, checks:[{check, pass,
/// detail, remedy}]}`; this build models the verdict as `{checks:[{name, status,
/// detail, remedy}], ready}` so a spawn failure has an honest `unknown` state the
/// boolean `pass` cannot express. The check ids, their fixed order, the frozen
/// `detail` tokens, the one-line remedies, and the top-level `osBuild` are kept
/// verbatim from the spec.)
public enum Doctor {
  /// Interpret the captured precondition inputs. Each argument is the raw output of
  /// one local read, or `nil` if that read could not be made.
  ///
  /// - Parameters:
  ///   - csrutil: stdout of `csrutil status` (SIP).
  ///   - nvramBootArgs: stdout of `nvram boot-args` (AMFI + arm64e ABI).
  ///   - arch: stdout of `uname -m` (the running arch).
  ///   - osBuild: stdout of `sw_vers` (carried by the CLI; not itself a check).
  ///   - libraryValidation: whether library validation is disabled, or `nil` if unread.
  ///   - uitoolBuilt: whether the arm64e injectable is present, or `nil` if unread.
  public static func report(
    csrutil: String?,
    nvramBootArgs: String?,
    arch: String?,
    osBuild: String?,
    libraryValidation: Bool?,
    uitoolBuilt: Bool?
  ) -> DoctorReport {
    DoctorReport(
      checks: [
        sipCheck(csrutil),
        amfiCheck(nvramBootArgs),
        libvalCheck(libraryValidation),
        arm64eABICheck(nvramBootArgs),
        archCheck(arch),
        uitoolBuiltCheck(uitoolBuilt),
      ],
      osBuild: osBuild?.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  // MARK: - per-check interpreters

  /// SIP passes when `csrutil status` reports it disabled (Permissive Security).
  private static func sipCheck(_ output: String?) -> PreconditionCheck {
    guard let output = output?.lowercased() else {
      return PreconditionCheck(name: "sip", status: .unknown, detail: "unread")
    }
    let disabled = output.contains("disabled") || output.contains("permissive")
    return disabled
      ? PreconditionCheck(name: "sip", status: .ok, detail: "disabled")
      : PreconditionCheck(
        name: "sip", status: .failed, detail: "enabled",
        remedy:
          "boot to Recovery and run: csrutil enable --without kext --without dtrace; csrutil authenticated-root disable"
      )
  }

  /// AMFI passes when `boot-args` carries `amfi_get_out_of_my_way=0x1` — the real gate.
  private static func amfiCheck(_ bootArgs: String?) -> PreconditionCheck {
    guard let bootArgs else {
      return PreconditionCheck(name: "amfi", status: .unknown, detail: "unread")
    }
    return bootArgs.contains("amfi_get_out_of_my_way=0x1")
      ? PreconditionCheck(name: "amfi", status: .ok, detail: "disabled")
      : PreconditionCheck(
        name: "amfi", status: .failed, detail: "enforcing",
        remedy:
          "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot")
  }

  /// Library validation passes when the override disables it.
  private static func libvalCheck(_ disabled: Bool?) -> PreconditionCheck {
    guard let disabled else {
      return PreconditionCheck(name: "libval", status: .unknown, detail: "unread")
    }
    return disabled
      ? PreconditionCheck(name: "libval", status: .ok, detail: "disabled")
      : PreconditionCheck(
        name: "libval", status: .failed, detail: "enabled",
        remedy:
          "sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool true"
      )
  }

  /// The arm64e preview ABI passes when `boot-args` carries `-arm64e_preview_abi`.
  private static func arm64eABICheck(_ bootArgs: String?) -> PreconditionCheck {
    guard let bootArgs else {
      return PreconditionCheck(name: "arm64e-abi", status: .unknown, detail: "unread")
    }
    return bootArgs.contains("-arm64e_preview_abi")
      ? PreconditionCheck(name: "arm64e-abi", status: .ok, detail: "present")
      : PreconditionCheck(
        name: "arm64e-abi", status: .failed, detail: "absent",
        remedy:
          "sudo nvram boot-args=\"amfi_get_out_of_my_way=0x1 -arm64e_preview_abi\" && reboot")
  }

  /// The arch check passes on the Apple Silicon family — `uname -m` reports `arm64`
  /// on an arm64e-capable host (the `e` ABI variant is a per-binary build flavor,
  /// not a kernel arch `uname` ever prints), so both `arm64` and `arm64e` pass. It
  /// fails on `x86_64`, where arm64e injection is impossible. The `detail` is the
  /// concrete reported arch, per the spec's "the built arch" failure token.
  ///
  /// (deviates: the spec's arch check reads the *injectable's* build slice via
  /// `file`/`lipo` — that injectable is part of the deferred injection half and is
  /// not yet built; this build reads the *host* arch via `uname -m` (the task's
  /// mandated probe) as the necessary Apple-Silicon precondition, and accepts
  /// `arm64` because that is what `uname` reports on an arm64e host.)
  private static func archCheck(_ arch: String?) -> PreconditionCheck {
    guard let arch = arch?.trimmingCharacters(in: .whitespacesAndNewlines), !arch.isEmpty else {
      return PreconditionCheck(name: "arch", status: .unknown, detail: "unread")
    }
    let appleSilicon = arch == "arm64" || arch == "arm64e"
    return appleSilicon
      ? PreconditionCheck(name: "arch", status: .ok, detail: arch)
      : PreconditionCheck(
        name: "arch", status: .failed, detail: arch,
        remedy: "run uitool on an Apple Silicon (arm64e-capable) host")
  }

  /// The injectable-built check passes when `UIToolBoot` is on disk.
  private static func uitoolBuiltCheck(_ present: Bool?) -> PreconditionCheck {
    guard let present else {
      return PreconditionCheck(name: "uitool-built", status: .unknown, detail: "unread")
    }
    return present
      ? PreconditionCheck(name: "uitool-built", status: .ok, detail: "present")
      : PreconditionCheck(
        name: "uitool-built", status: .failed, detail: "absent",
        remedy: "build the arm64e UIToolBoot injectable (the injection half is not yet built)")
  }
}
