import Foundation

// SPEC: domain.uitool.selector
/// The one matching engine `*=` (substring), `matches` (regex), and `~`
/// (class-of / hierarchy) share — so the contract is stated once and can never
/// drift between the selector and predicate forms.
///
/// Regex is Swift-native `Regex`, **never** `NSRegularExpression`. The semantics
/// are pinned by the spec: case-insensitive, unanchored substring — a pattern
/// matches if it occurs *anywhere* in the candidate (`firstMatch`, not a
/// whole-string anchor), folding case. To anchor, the caller writes the anchors
/// into the pattern. An uncompilable pattern is a `BAD_SELECTOR` usage error,
/// surfaced at construction so a malformed pattern is rejected before any node is
/// touched — never silently treated as a literal or a zero-match.
enum MatchEngine {

  /// A compiled, case-insensitive, unanchored regex. Construction throws
  /// `BAD_SELECTOR` on an uncompilable pattern — the only place a pattern can fail,
  /// and it fails before the tree is walked.
  ///
  /// `@unchecked Sendable`: a `Regex` is not `Sendable` in the stdlib (it can carry
  /// non-`Sendable` capture transforms in general), but this one is compiled once
  /// from a string, is immutable thereafter, and `firstMatch` is non-mutating — so
  /// the compiled query value crosses concurrency domains safely, keeping the whole
  /// selector/predicate AST `Sendable` like the rest of the value types here.
  struct Pattern: @unchecked Sendable {
    private let regex: Regex<AnyRegexOutput>

    /// Compile `pattern` case-insensitively, or throw `badSelector`. `Regex(_:)`
    /// itself throws on an invalid pattern; the catch maps it onto the wire code.
    init(_ pattern: String) throws {
      do {
        self.regex = try Regex(pattern).ignoresCase()
      } catch {
        throw UIToolError.badSelector(pattern)
      }
    }

    /// Compile a `*=` substring as a regex over a literal-escaped needle. Because
    /// the needle is escaped, `*=` can never itself throw on metacharacters — only
    /// an explicit `matches` regex can be a bad selector (the spec's `*=`-is-sugar
    /// rule).
    static func substring(_ needle: String) throws -> Pattern {
      try Pattern(NSRegularExpression.escapedPattern(for: needle))
    }

    /// `true` when the pattern occurs anywhere in `candidate` — `firstMatch`, not a
    /// whole-string match, so the semantics are unanchored substring.
    func matches(_ candidate: String) -> Bool {
      guard let match = try? regex.firstMatch(in: candidate) else { return false }
      return match != nil
    }
  }

  /// `true` when `candidate` *is* `className` or has it anywhere in its runtime
  /// superclass chain — the `~` class-of / hierarchy test. The chain is the
  /// snapshot's `superclasses` (immediate superclass up to `NSObject`, exclusive of
  /// the node's own class), so `NSControl ~ NSButton` resolves through that chain,
  /// the capability AX (roles, not classes) fundamentally cannot offer. Matching is
  /// exact class-name equality at each rung, case-sensitive — class names are not
  /// patterns.
  static func isKind(_ node: Node, ofClass className: String, in tree: NodeTree) -> Bool {
    if node.class == className { return true }
    return tree.superclasses(of: node).contains(className)
  }
}
