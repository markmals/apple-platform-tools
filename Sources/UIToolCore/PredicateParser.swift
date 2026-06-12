import Foundation

// SPEC: domain.uitool.selector
/// A recursive-descent parser for the `--where` expression language. Precedence,
/// lowest to highest: `or` < `and` < `not` < primary (a comparison, a `~`
/// class-of test, or a parenthesized sub-expression). The recursion is on the
/// grammar, not the input, and the input is consumed left to right exactly once —
/// the depth is bounded by the parentheses/`not` count in the source, so parsing
/// is bounded and total. Any structural error is a `BAD_PREDICATE`.
///
/// Tokens are split out by `PredicateLexer` first, so this layer reasons about a
/// flat token list, never raw characters.
struct PredicateParser {
  private let tokens: [PredicateToken]
  private var index = 0

  init(_ source: String) {
    self.tokens = PredicateLexer.tokenize(source)
  }

  /// Parse the whole expression and require the input to be fully consumed —
  /// trailing tokens (`hidden = false foo`) are a malformed predicate.
  mutating func parse() throws -> Expression {
    let expression = try parseOr()
    guard index >= tokens.count else {
      throw UIToolError.badPredicate("unexpected trailing input")
    }
    return expression
  }

  /// `or` — the lowest-precedence binary connective, left-associative.
  private mutating func parseOr() throws -> Expression {
    var lhs = try parseAnd()
    while consumeKeyword("or") {
      lhs = .or(lhs, try parseAnd())
    }
    return lhs
  }

  /// `and` — binds tighter than `or`, left-associative.
  private mutating func parseAnd() throws -> Expression {
    var lhs = try parseNot()
    while consumeKeyword("and") {
      lhs = .and(lhs, try parseNot())
    }
    return lhs
  }

  /// `not` — a unary prefix binding tighter than `and`.
  private mutating func parseNot() throws -> Expression {
    if consumeKeyword("not") {
      return .not(try parseNot())
    }
    return try parsePrimary()
  }

  /// A primary: a parenthesized sub-expression, or a comparison/`~` leaf.
  private mutating func parsePrimary() throws -> Expression {
    if consumeSymbol("(") {
      let inner = try parseOr()
      guard consumeSymbol(")") else { throw UIToolError.badPredicate("expected ')'") }
      return inner
    }
    return try parseLeaf()
  }

  /// A leaf comparison: `attr op value`. The attribute is resolved (throws
  /// `UNKNOWN_FIELD` if unknown); `~` builds a class-of test; every other operator
  /// builds a value comparison.
  private mutating func parseLeaf() throws -> Expression {
    let attributePath = try takeWord("an attribute name")
    let attribute = try Attribute.resolve(attributePath)
    let op = try takeOperator()
    let literal = try takeLiteral()

    if op == .classOf {
      return .classOf(attribute, literal.text)
    }
    guard let selectorOp = op.selectorOperator else {
      throw UIToolError.badPredicate("unexpected operator")
    }
    return .comparison(attribute, try selectorOp.comparison(for: literal))
  }

  // MARK: - Token cursor

  private func peek() -> PredicateToken? {
    index < tokens.count ? tokens[index] : nil
  }

  /// Consume a keyword token (`and`/`or`/`not`) if it is next, case-insensitively.
  private mutating func consumeKeyword(_ keyword: String) -> Bool {
    guard case .word(let word)? = peek(), word.lowercased() == keyword else { return false }
    index += 1
    return true
  }

  /// Consume a symbol token (`(`/`)`) if it is next.
  private mutating func consumeSymbol(_ symbol: String) -> Bool {
    guard case .symbol(let value)? = peek(), value == symbol else { return false }
    index += 1
    return true
  }

  /// Take a bare word token (an attribute name), or throw `BAD_PREDICATE`.
  private mutating func takeWord(_ expectation: String) throws -> String {
    guard case .word(let word)? = peek() else {
      throw UIToolError.badPredicate("expected \(expectation)")
    }
    index += 1
    return word
  }

  /// Take an operator token, or throw `BAD_PREDICATE`.
  private mutating func takeOperator() throws -> PredicateOperatorToken {
    guard case .op(let op)? = peek() else {
      throw UIToolError.badPredicate("expected a comparison operator")
    }
    index += 1
    return op
  }

  /// Take the right-hand literal — a quoted string, a number, or a bareword
  /// (`true`/`false`/a class name). Throws `BAD_PREDICATE` when none is present.
  private mutating func takeLiteral() throws -> SelectorLiteral {
    switch peek() {
    case .string(let text)?:
      index += 1
      return SelectorLiteral(text: text, wasQuoted: true)
    case .word(let word)?:
      index += 1
      return SelectorLiteral(text: word, wasQuoted: false)
    default:
      throw UIToolError.badPredicate("expected a value")
    }
  }
}
