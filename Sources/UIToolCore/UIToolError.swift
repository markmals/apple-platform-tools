import AgentCLI

// SPEC: domain.uitool.ipc
/// The closed `uitool` error vocabulary, paired with the CLI exit code each maps
/// to. The pure core throws these; the (deferred) injected server and the CLI
/// translate them onto the wire envelope and the process exit code respectively.
///
/// The codes are drawn verbatim from [[domain.uitool.ipc]]'s closed vocabulary —
/// no ad-hoc strings, no placeholders. `UNKNOWN_FIELD` and `BAD_PREDICATE` are
/// deliberately *distinct* from `BAD_SELECTOR` (all exit 2, but different
/// agent-fixable mistakes). `NO_WINDOWS` is **not** itself an error exit — an
/// attached app with zero windows is a valid empty result — so it maps to exit 0;
/// it is only carried as the explanatory `error.code` on stderr where a verb that
/// requires a window to root at cannot proceed.
public enum UIToolError: Error, Equatable {
  /// An uncompilable `--match` / `matches` regex, or a usage/selector error.
  case badSelector(String)
  /// A `--fields` path that names no field on [[domain.uitool.node]].
  case unknownField(String)
  /// A malformed `--where` predicate the grammar cannot parse.
  case badPredicate(String)
  /// A held node id failed re-validation against the live graph.
  case staleNode(NodeID)
  /// No live session for the target (or injection failed).
  case notAttached
  /// `attach`: the named target process does not exist (exit 3, attach-time only).
  case appNotRunning(String)
  /// `launch`: no launchable app resolves for the bundle id / path (exit 3).
  case appNotFound(String)
  /// Injection did not take — the inserted dylib never opened its socket within the
  /// bounded wait (exit 4, attach/launch-time).
  case injectionFailed(String)
  /// The attached app has no top-level window to root a required read at. A valid
  /// empty result, never a failure exit (exit 0).
  case noWindows
  /// A main-thread hop exceeded the bound, or a socket timed out.
  case timeout
  /// An injection precondition is unmet — `doctor`'s not-ready verdict (and the
  /// future `attach` gate). The detail names the failed checks.
  case preconditionFailed(String)
  /// The injected server reports a protocol/schema version the CLI does not speak
  /// — the separately-built CLI and dylib have desynced ([[domain.uitool.ipc]]).
  case schemaMismatch(String)

  /// The wire `error.code` string — the closed vocabulary the agent branches on
  /// without parsing prose.
  public var code: String {
    switch self {
    case .badSelector: return "BAD_SELECTOR"
    case .unknownField: return "UNKNOWN_FIELD"
    case .badPredicate: return "BAD_PREDICATE"
    case .staleNode: return "STALE_NODE"
    case .notAttached: return "NOT_ATTACHED"
    case .appNotRunning: return "APP_NOT_RUNNING"
    case .appNotFound: return "APP_NOT_FOUND"
    case .injectionFailed: return "INJECTION_FAILED"
    case .noWindows: return "NO_WINDOWS"
    case .timeout: return "TIMEOUT"
    case .preconditionFailed: return "PRECONDITION_FAILED"
    case .schemaMismatch: return "SCHEMA_MISMATCH"
    }
  }

  /// The CLI exit code, per [[domain.uitool.ipc]]'s exit-code mapping. `NO_WINDOWS`
  /// is an empty result, not a failure, so it returns `0`.
  public var exitCode: Int32 {
    switch self {
    case .badSelector, .unknownField, .badPredicate: return 2
    case .appNotRunning, .appNotFound: return 3
    case .notAttached, .injectionFailed: return 4
    case .staleNode: return 5
    case .preconditionFailed: return 6
    case .timeout: return 7
    case .noWindows: return 0
    case .schemaMismatch: return 8
    }
  }

  /// Map a wire `error` object back to the closed vocabulary so the CLI exits on
  /// the right code without parsing prose. An unrecognized code is treated as a
  /// usage error (exit 2) rather than silently swallowed.
  public static func from(wire: WireError) -> UIToolError {
    switch wire.code {
    case "BAD_SELECTOR": return .badSelector(wire.message)
    case "UNKNOWN_FIELD": return .unknownField(wire.message)
    case "BAD_PREDICATE": return .badPredicate(wire.message)
    case "NOT_ATTACHED": return .notAttached
    case "NO_WINDOWS": return .noWindows
    case "TIMEOUT": return .timeout
    case "SCHEMA_MISMATCH": return .schemaMismatch(wire.message)
    default: return .badSelector(wire.message)
    }
  }
}

// SPEC: domain.uitool.ipc
extension UIToolError: AgentError {
  /// The stderr diagnostic: the closed wire `code` plus the offending detail, so a
  /// reader sees both the branchable code and what triggered it.
  public var message: String {
    switch self {
    case .badSelector(let detail): return "\(code): \(detail)"
    case .unknownField(let path): return "\(code): \(path)"
    case .badPredicate(let detail): return "\(code): \(detail)"
    case .staleNode(let id): return "\(code): \(id)"
    case .notAttached: return "\(code): no attached uitool session for the target"
    case .appNotRunning(let detail): return "\(code): \(detail)"
    case .appNotFound(let detail): return "\(code): \(detail)"
    case .injectionFailed(let detail): return "\(code): \(detail)"
    case .noWindows: return "\(code): the attached app has no top-level windows"
    case .timeout: return "\(code): the main-thread read or socket timed out"
    case .preconditionFailed(let detail): return "\(code): \(detail)"
    case .schemaMismatch(let detail): return "\(code): \(detail)"
    }
  }
}
