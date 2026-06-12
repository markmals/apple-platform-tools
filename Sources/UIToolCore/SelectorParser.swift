import Foundation

// SPEC: domain.uitool.selector
/// A hand-written recursive-descent parser for the structural-selector grammar.
/// Bounded and total: it scans the input once, left to right, producing a flat
/// chain of compound selectors and the combinators between them. No backtracking,
/// no recursion on the input — the grammar is a simple sequence.
///
/// Grammar (informally):
/// ```
/// selector   := compound ( combinator compound )*
/// combinator := WS | '>' (surrounding WS optional)
/// compound   := ( class | '*' ) attr*        // a bare attr* (just '[…]') is also a compound
/// class      := IDENT                          // NSButton, _NSToolbarView
/// attr       := '[' IDENT op value ']'
/// op         := '*=' | '>=' | '<=' | '!=' | '=' | '>' | '<'
/// value      := quoted | bareword | number
/// ```
struct SelectorParser {
  private let scanner: Scanner

  init(_ input: String) {
    self.scanner = Scanner(input)
  }

  /// Parse the whole selector. Throws `BAD_SELECTOR` on malformed structure (an
  /// unterminated `[`, a missing operator, a trailing combinator) and on an
  /// uncompilable `[attr matches …]`; `UNKNOWN_FIELD` on an unrecognized attribute.
  mutating func parse() throws -> ([CompoundSelector], [Combinator]) {
    var compounds: [CompoundSelector] = []
    var combinators: [Combinator] = []

    compounds.append(try parseCompound())
    while let combinator = try parseCombinator() {
      combinators.append(combinator)
      compounds.append(try parseCompound())
    }
    // The whole input must be consumed. Trailing junk a combinator did not pick up
    // (`NSButton @x`, or the unsupported glob `NS*View` whose `*View` is left over)
    // is a malformed selector, never silently ignored.
    scanner.skipWhitespaceDiscarding()
    guard scanner.isAtEnd else {
      throw UIToolError.badSelector("unexpected trailing input in selector")
    }
    return (compounds, combinators)
  }

  /// Read a combinator between compounds, or `nil` at end of input. A `>` (with
  /// optional surrounding whitespace) is a child combinator; whitespace alone is a
  /// descendant combinator. A `>` with nothing after it is a malformed selector.
  private mutating func parseCombinator() throws -> Combinator? {
    let hadWhitespace = scanner.skipWhitespace()
    if scanner.isAtEnd { return nil }
    if scanner.consume(">") {
      scanner.skipWhitespaceDiscarding()
      if scanner.isAtEnd { throw UIToolError.badSelector("dangling '>' combinator") }
      return .child
    }
    return hadWhitespace ? .descendant : nil
  }

  /// Read one compound selector: an optional class token (or `*`), then zero or
  /// more `[attr op value]` predicates. A compound with neither a class nor any
  /// attribute is a malformed selector (an empty selector segment).
  private mutating func parseCompound() throws -> CompoundSelector {
    let isWildcard = scanner.consume("*")
    let className = isWildcard ? nil : parseClassToken()
    var attributes: [AttributeSelector] = []
    while scanner.peek() == "[" {
      attributes.append(try parseAttribute())
    }
    // A `nil` class means "any class" — valid when it came from an explicit `*`
    // wildcard or from `[attr…]` attributes. Only a segment that is *neither* a
    // wildcard, nor a class, nor an attribute is an empty (malformed) compound.
    if !isWildcard, className == nil, attributes.isEmpty {
      throw UIToolError.badSelector("empty compound selector")
    }
    return CompoundSelector(className: className, attributes: attributes)
  }

  /// Read a class-name identifier, or `nil` when the compound leads with `[` (an
  /// attribute-only compound). The wildcard `*` is consumed in `parseCompound`.
  private mutating func parseClassToken() -> String? {
    let identifier = scanner.takeIdentifier()
    return identifier.isEmpty ? nil : identifier
  }

  /// Read one `[attr op value]` predicate. Resolves the attribute (throws
  /// `UNKNOWN_FIELD` if unknown) and builds the comparison (compiling a `matches`
  /// pattern eagerly, throwing `BAD_SELECTOR` if it won't compile).
  private mutating func parseAttribute() throws -> AttributeSelector {
    guard scanner.consume("[") else { throw UIToolError.badSelector("expected '['") }
    scanner.skipWhitespaceDiscarding()
    let attributePath = scanner.takeIdentifier()
    let attribute = try Attribute.resolve(attributePath)
    scanner.skipWhitespaceDiscarding()
    let op = try scanner.takeOperator()
    scanner.skipWhitespaceDiscarding()
    let value = try scanner.takeAttributeValue()
    scanner.skipWhitespaceDiscarding()
    guard scanner.consume("]") else {
      throw UIToolError.badSelector("unterminated attribute selector")
    }
    return AttributeSelector(attribute: attribute, test: try selectorComparison(op, value))
  }

  /// Build a comparison in *selector* context: a malformed value (a non-numeric
  /// geometry operand) is a `BAD_SELECTOR`, not a `BAD_PREDICATE`, so the shared
  /// `badPredicate` the operator layer raises is re-mapped here. An uncompilable
  /// `matches` pattern already raises `badSelector` and passes through unchanged.
  private func selectorComparison(_ op: SelectorOperator, _ value: SelectorLiteral) throws
    -> Comparison
  {
    do {
      return try op.comparison(for: value)
    } catch UIToolError.badPredicate(let message) {
      throw UIToolError.badSelector(message)
    }
  }
}

// SPEC: domain.uitool.selector
/// A minimal left-to-right character scanner over the selector text — the lexing
/// primitive the parser drives. Holds a cursor into the string's characters; every
/// `take`/`consume` advances it. Keeps the parser free of index arithmetic.
private final class Scanner {
  private let characters: [Character]
  private var index = 0

  init(_ input: String) {
    self.characters = Array(input)
  }

  var isAtEnd: Bool { index >= characters.count }

  func peek() -> Character? { isAtEnd ? nil : characters[index] }

  /// Advance past `character` if it is next; report whether it was consumed.
  func consume(_ character: Character) -> Bool {
    guard peek() == character else { return false }
    index += 1
    return true
  }

  /// Skip a run of whitespace; report whether any was skipped (a descendant
  /// combinator is "whitespace was present").
  @discardableResult
  func skipWhitespace() -> Bool {
    let start = index
    while let character = peek(), character.isWhitespace { index += 1 }
    return index > start
  }

  /// Skip whitespace without reporting — used after a `>` where the presence of
  /// surrounding whitespace is irrelevant.
  func skipWhitespaceDiscarding() { _ = skipWhitespace() }

  /// Take an identifier run: letters, digits, `_`, `-`, `.`. Covers class names
  /// (`NSButton`, `_NSToolbar`) and attribute paths (`frame-w`, `font.family`).
  func takeIdentifier() -> String {
    var result = ""
    while let character = peek(),
      character.isLetter || character.isNumber || "_-.".contains(character)
    {
      result.append(character)
      index += 1
    }
    return result
  }

  /// Take a comparison operator. Longest-match first so `>=` is not read as `>`.
  /// Throws `BAD_SELECTOR` when no operator is present.
  func takeOperator() throws -> SelectorOperator {
    for candidate in SelectorOperator.byLongestToken where matchLiteral(candidate.token) {
      return candidate
    }
    throw UIToolError.badSelector("expected a comparison operator")
  }

  /// Take an attribute value: a quoted string (single or double), or a bareword /
  /// number run up to the closing `]`. Quotes are stripped; the literal kind
  /// (quoted text vs bareword) is preserved so the parser can tag bool/number.
  func takeAttributeValue() throws -> SelectorLiteral {
    if let quote = peek(), quote == "\"" || quote == "'" {
      return SelectorLiteral(text: try takeQuoted(quote), wasQuoted: true)
    }
    var raw = ""
    while let character = peek(), character != "]" {
      raw.append(character)
      index += 1
    }
    return SelectorLiteral(text: raw.trimmingCharacters(in: .whitespaces), wasQuoted: false)
  }

  /// Read a quoted run, consuming the closing quote. Throws on an unterminated
  /// quote. No escape processing — selectors are simple and a literal quote in a
  /// value is out of scope for v1.
  private func takeQuoted(_ quote: Character) throws -> String {
    index += 1
    var result = ""
    while let character = peek(), character != quote {
      result.append(character)
      index += 1
    }
    guard consume(quote) else { throw UIToolError.badSelector("unterminated string literal") }
    return result
  }

  /// Consume a multi-character literal if it is next; report whether it matched.
  private func matchLiteral(_ literal: String) -> Bool {
    let tokens = Array(literal)
    guard index + tokens.count <= characters.count else { return false }
    guard Array(characters[index..<index + tokens.count]) == tokens else { return false }
    index += tokens.count
    return true
  }
}
