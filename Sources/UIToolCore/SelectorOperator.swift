// SPEC: domain.uitool.selector
/// The value-level operators shared by `[attr op value]` selectors and `--where`
/// comparison leaves: the six relational operators plus `*=` substring and
/// `matches` regex. Each carries its surface token (for longest-match lexing) and
/// knows how to build a `Comparison` from a parsed literal — the single place the
/// operator's meaning is defined, so the selector and predicate parsers agree by
/// construction.
///
/// `~` (class-of / hierarchy) is deliberately **absent** here: it is not a value
/// comparison — it resolves a class name against the runtime hierarchy through the
/// tree — so it is handled one layer up, in `Predicate`, where the tree is in hand.
enum SelectorOperator: CaseIterable {
  case equal
  case notEqual
  case greaterOrEqual
  case lessOrEqual
  case greater
  case less
  case substring
  case matchesRegex

  /// The surface token.
  var token: String {
    switch self {
    case .equal: return "="
    case .notEqual: return "!="
    case .greaterOrEqual: return ">="
    case .lessOrEqual: return "<="
    case .greater: return ">"
    case .less: return "<"
    case .substring: return "*="
    case .matchesRegex: return "matches"
    }
  }

  /// The operators ordered so a multi-character token is tried before any prefix of
  /// it — `>=` before `>`, `*=` before `=`, `!=` before `=` — so the lexer never
  /// truncates a two-character operator into a one-character one.
  static var byLongestToken: [SelectorOperator] {
    allCases.sorted { $0.token.count > $1.token.count }
  }

  /// Build the `Comparison` this operator means for a parsed literal. An ordering
  /// operator demands a number (a non-numeric operand is `BAD_PREDICATE`); a
  /// `matches` operator compiles its regex eagerly (`BAD_SELECTOR` on a bad
  /// pattern). `=`/`!=` keep the literal's domain so `hidden = false` is a bool and
  /// `childCount = 3` a number.
  func comparison(for literal: SelectorLiteral) throws -> Comparison {
    switch self {
    case .equal: return .equal(literal.operand)
    case .notEqual: return .notEqual(literal.operand)
    case .greater: return .greater(try literal.requireNumber())
    case .less: return .less(try literal.requireNumber())
    case .greaterOrEqual: return .greaterOrEqual(try literal.requireNumber())
    case .lessOrEqual: return .lessOrEqual(try literal.requireNumber())
    case .substring: return .substring(try MatchEngine.Pattern.substring(literal.text))
    case .matchesRegex: return .matches(try MatchEngine.Pattern(literal.text))
    }
  }
}

// SPEC: domain.uitool.selector
/// A parsed value literal plus whether it was quoted — enough to recover its
/// comparison domain. An unquoted `true`/`false` is a bool, an unquoted numeric
/// run is a number, and anything quoted (or otherwise) is text. The quote flag is
/// what lets `[hidden=false]` mean the bool `false` while `[title="false"]` means
/// the string.
struct SelectorLiteral {
  let text: String
  let wasQuoted: Bool

  /// The `=`/`!=` operand, in the domain the literal implies.
  var operand: Operand {
    if !wasQuoted {
      if text == "true" { return .bool(true) }
      if text == "false" { return .bool(false) }
      if let number = Double(text) { return .number(number) }
    }
    return .text(text)
  }

  /// The numeric value for an ordering operator, or `BAD_PREDICATE` when the
  /// literal is not a number (`frame-w > big` is a usage error, not a 0-match).
  func requireNumber() throws -> Double {
    guard let number = Double(text) else {
      throw UIToolError.badPredicate("expected a number, got '\(text)'")
    }
    return number
  }
}
