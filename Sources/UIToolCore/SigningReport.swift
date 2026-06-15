// SPEC: command.uitool.signing
/// A target's code-signing profile, reduced to the facts that decide injectability
/// ([[command.uitool.signing]]). The effectful Security-framework read is the CLI's;
/// this is the plain projected shape plus the pure verdict.
public struct SigningReport: Encodable, Sendable {
  public let target: String
  public let signed: Bool
  public let identifier: String?
  public let teamId: String?
  /// "ad-hoc", the leaf authority's common name, or "unsigned".
  public let authority: String
  public let hardenedRuntime: Bool
  public let sandboxed: Bool
  public let getTaskAllow: Bool
  /// The injection-relevant entitlements only (not the full plist).
  public let entitlements: [String: JSONValue]
  /// The derived Posture-1 verdict ([[domain.uitool.injection]]).
  public let cooperativeInjectable: Bool

  public init(
    target: String, signed: Bool, identifier: String?, teamId: String?, authority: String,
    hardenedRuntime: Bool, sandboxed: Bool, getTaskAllow: Bool, entitlements: [String: JSONValue],
    cooperativeInjectable: Bool
  ) {
    self.target = target
    self.signed = signed
    self.identifier = identifier
    self.teamId = teamId
    self.authority = authority
    self.hardenedRuntime = hardenedRuntime
    self.sandboxed = sandboxed
    self.getTaskAllow = getTaskAllow
    self.entitlements = entitlements
    self.cooperativeInjectable = cooperativeInjectable
  }
}

// SPEC: command.uitool.signing
/// The cooperative-injectability verdict — pure, so it is unit-tested without the
/// Security framework. Encodes Posture 1's per-target preconditions
/// ([[domain.uitool.injection]]).
public enum SigningVerdict {
  /// A `get-task-allow` target is cooperatively injectable on a stock Mac when its
  /// hardened runtime is off, **or** it grants both the dyld-environment and
  /// disable-library-validation overrides (so `DYLD_INSERT` and a non-Apple dylib
  /// are honored). Without `get-task-allow`, it needs the unrestricted posture.
  public static func cooperativeInjectable(
    getTaskAllow: Bool, hardenedRuntime: Bool, allowsDyldEnv: Bool, disablesLibval: Bool
  ) -> Bool {
    guard getTaskAllow else { return false }
    return !hardenedRuntime || (allowsDyldEnv && disablesLibval)
  }
}
