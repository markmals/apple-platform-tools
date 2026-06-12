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
  /// The attached app has no top-level window to root a required read at. A valid
  /// empty result, never a failure exit (exit 0).
  case noWindows
  /// A main-thread hop exceeded the bound, or a socket timed out.
  case timeout

  /// The wire `error.code` string — the closed vocabulary the agent branches on
  /// without parsing prose.
  public var code: String {
    switch self {
    case .badSelector: return "BAD_SELECTOR"
    case .unknownField: return "UNKNOWN_FIELD"
    case .badPredicate: return "BAD_PREDICATE"
    case .staleNode: return "STALE_NODE"
    case .notAttached: return "NOT_ATTACHED"
    case .noWindows: return "NO_WINDOWS"
    case .timeout: return "TIMEOUT"
    }
  }

  /// The CLI exit code, per [[domain.uitool.ipc]]'s exit-code mapping. `NO_WINDOWS`
  /// is an empty result, not a failure, so it returns `0`.
  public var exitCode: Int32 {
    switch self {
    case .badSelector, .unknownField, .badPredicate: return 2
    case .notAttached: return 4
    case .staleNode: return 5
    case .timeout: return 7
    case .noWindows: return 0
    }
  }
}
