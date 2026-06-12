import Foundation

// SPEC: command.uitool.doctor
/// One precondition's verdict. `name` is the frozen check id from
/// [[command.uitool.doctor]] (`sip` / `amfi` / `libval` / `arm64e-abi` / `arch` /
/// `injectable-arm64` / `injectable-arm64e`); `detail` is the spec's byte-stable
/// token, never free prose; `remedy` is the one-line fix, present only on a failed
/// check.
///
/// `status` carries one extra state the spec's `pass: Bool` cannot: `unknown`,
/// for a check whose underlying command could not be read (the spawn failed). A
/// spawn failure must never crash `doctor` and must not masquerade as a pass — it
/// is an honest "couldn't tell", and an `unknown` check leaves a posture not-usable
/// just like a failure does.
public struct PreconditionCheck: Codable, Equatable, Sendable {
  /// The frozen check id (`sip`, `amfi`, `libval`, `arm64e-abi`, `arch`,
  /// `injectable-arm64`, `injectable-arm64e`).
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
/// One injection posture's readiness. macOS gates injection per target, and which
/// gate applies depends on who controls the target's code signing — so the report
/// carries *two* postures, and an agent reads which targets it can attach to from
/// here.
///
/// - `usable` is true only when *every* `requires` check is `.ok`; a single
///   `failed` or `unknown` check leaves the posture not-usable.
/// - `requires` is this posture's check array in fixed order.
/// - `note` is the one-line description of what this posture is for.
public struct ModeReport: Codable, Equatable, Sendable {
  /// True only when every check in `requires` is `.ok`.
  public let usable: Bool
  /// This posture's precondition checks, in fixed order.
  public let requires: [PreconditionCheck]
  /// One line: what this posture is for.
  public let note: String

  public init(requires: [PreconditionCheck], note: String) {
    self.usable = requires.allSatisfy { $0.status == .ok }
    self.requires = requires
    self.note = note
  }
}

// SPEC: command.uitool.doctor
/// The aggregate verdict across both injection postures.
///
/// macOS gates injection *per target*, and the gate that applies depends on who
/// controls the target's code signing — so readiness is not a single flag. The
/// `cooperative` posture inspects apps the user builds and signs for development
/// (a `get-task-allow` debug build); it is honored for task-port access and dyld
/// insertion regardless of SIP, exactly how lldb / Xcode / Reveal attach to your
/// own apps on a stock Mac — so it needs *no* machine defanging, only the arm64
/// boot dylib. The `unrestricted` posture inspects apps the user did *not* sign
/// (system / notarized), which ship hardened with library validation and no
/// per-app lever — so the only path is to lower protections machine-wide (the full
/// defang stack) and match the system frameworks' arm64e slice.
///
/// The CLI maps `cooperative.usable` to its exit code: 0 when the common case (your
/// own apps) is usable, otherwise 6. The defanged machine is required *only* for
/// non-cooperative targets.
public struct DoctorReport: Codable, Equatable, Sendable {
  /// Inspect your own `get-task-allow` apps; SIP may stay on.
  public let cooperative: ModeReport
  /// Inspect any app including system; needs the full defang.
  public let unrestricted: ModeReport
  /// The OS build (e.g. `26D5044f`) — precondition validity is OS-build-specific
  /// (arm64e injection regresses across Tahoe 26.x). Machine-specific, so it is
  /// normalized out of snapshot assertions like a session id; `nil` when `sw_vers`
  /// could not be read. Not itself a check — it never affects usability.
  public let osBuild: String?

  public init(cooperative: ModeReport, unrestricted: ModeReport, osBuild: String? = nil) {
    self.cooperative = cooperative
    self.unrestricted = unrestricted
    self.osBuild = osBuild
  }
}

// SPEC: command.uitool.doctor
/// The pure, total interpreter that turns already-captured command outputs into a
/// two-posture `DoctorReport`. It never spawns anything and never fails — the CLI
/// edge runs `csrutil status`, `nvram boot-args`, `uname -m`, `sw_vers`, the
/// library-validation plist read, and the two injectable-presence stats, then hands
/// the *results* here. A `nil` input means that read could not be made (the spawn
/// failed): the dependent check(s) become `unknown` rather than crashing or
/// silently passing.
///
/// The per-check interpreters (sip / amfi / libval / arm64e-abi / arch) and their
/// frozen `detail` tokens and one-line remedies are unchanged — what this build
/// adds is the *grouping* into two injection postures and the two arm64 vs arm64e
/// injectable checks.
///
/// (deviates: the spec's command JSON models a single `checks` array with a single
/// `ok`; this build groups the checks into `{cooperative, unrestricted}` ModeReports
/// because macOS gates injection per target and the cooperative path needs no
/// machine defanging — collapsing both postures into one `ready` flag would
/// over-claim that every target needs SIP off. The per-check ids, the frozen
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
  ///   - injectableArm64: whether the arm64 `UIToolBoot` injectable is present, or `nil` if unread.
  ///   - injectableArm64e: whether the arm64e `UIToolBoot` injectable is present, or `nil` if unread.
  public static func report(
    csrutil: String?,
    nvramBootArgs: String?,
    arch: String?,
    osBuild: String?,
    libraryValidation: Bool?,
    injectableArm64: Bool?,
    injectableArm64e: Bool?
  ) -> DoctorReport {
    // Cooperative: inspect apps you build and sign for development. The
    // get-task-allow opt-in is honored regardless of SIP, so the *machine* only has
    // to be Apple Silicon and carry the arm64 boot dylib — no SIP/AMFI/libval lever.
    // (The per-target get-task-allow + dyld-env preconditions are checked at
    // attach/launch, not by this machine doctor.)
    let cooperative = ModeReport(
      requires: [
        archCheck(arch),
        injectableArm64Check(injectableArm64),
      ],
      note:
        "Inspect apps you build and sign for development (get-task-allow). No SIP / AMFI / library-validation changes — your machine is already capable."
    )

    // Unrestricted: inspect apps you did NOT sign (system / notarized). With no
    // per-app opt-in, the only path is to lower protections machine-wide — the full
    // defang stack — and match the system frameworks' arm64e slice.
    let unrestricted = ModeReport(
      requires: [
        sipCheck(csrutil),
        amfiCheck(nvramBootArgs),
        libvalCheck(libraryValidation),
        arm64eABICheck(nvramBootArgs),
        archCheck(arch),
        injectableArm64eCheck(injectableArm64e),
      ],
      note:
        "Additionally required only to inspect apps you did NOT sign (system / notarized). Dedicated dev box; reversible from Recovery."
    )

    return DoctorReport(
      cooperative: cooperative,
      unrestricted: unrestricted,
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
  /// fails on `x86_64`, where injection of the system frameworks is impossible. The
  /// `detail` is the concrete reported arch, per the spec's "the built arch" token.
  ///
  /// Shared by both postures: cooperative needs an Apple Silicon host because a
  /// stock Xcode app is arm64; unrestricted needs one because the shared cache is
  /// arm64e on Apple Silicon.
  ///
  /// (deviates: the spec's arch check reads the *injectable's* build slice via
  /// `file`/`lipo`; this build reads the *host* arch via `uname -m` (the task's
  /// mandated probe) as the necessary Apple-Silicon precondition, and accepts
  /// `arm64` because that is what `uname` reports on an arm64e host. The injectable's
  /// own slice is verified by the `injectable-arm64` / `injectable-arm64e` checks.)
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

  /// The arm64 injectable check passes when the arm64 `UIToolBoot` is on disk — the
  /// slice the cooperative path inserts into a stock (arm64) Xcode app.
  private static func injectableArm64Check(_ present: Bool?) -> PreconditionCheck {
    guard let present else {
      return PreconditionCheck(name: "injectable-arm64", status: .unknown, detail: "unread")
    }
    return present
      ? PreconditionCheck(name: "injectable-arm64", status: .ok, detail: "present")
      : PreconditionCheck(
        name: "injectable-arm64", status: .failed, detail: "absent",
        remedy: "build the arm64 UIToolBoot injectable (the injection half is not yet built)")
  }

  /// The arm64e injectable check passes when the arm64e `UIToolBoot` is on disk — the
  /// slice the unrestricted path needs to match the arm64e system frameworks.
  private static func injectableArm64eCheck(_ present: Bool?) -> PreconditionCheck {
    guard let present else {
      return PreconditionCheck(name: "injectable-arm64e", status: .unknown, detail: "unread")
    }
    return present
      ? PreconditionCheck(name: "injectable-arm64e", status: .ok, detail: "present")
      : PreconditionCheck(
        name: "injectable-arm64e", status: .failed, detail: "absent",
        remedy: "build the arm64e UIToolBoot injectable (the injection half is not yet built)")
  }
}
