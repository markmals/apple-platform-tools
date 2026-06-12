import Foundation

// SPEC: domain.uitool.selector
/// One lexical token of a `--where` source. The predicate grammar is small enough
/// that four kinds cover it: a bare word (an attribute name, a keyword, a class
/// name, `true`/`false`), a quoted string literal, an operator, or a `(`/`)`
/// grouping symbol. Lexing is total — an unrecognized character is dropped as
/// whitespace would be, and a structural error surfaces at *parse* time, where the
/// grammar gives it meaning, not here.
enum PredicateToken: Equatable {
  case word(String)
  case string(String)
  case op(PredicateOperatorToken)
  case symbol(String)
}

// SPEC: domain.uitool.selector
/// A `--where` operator token. Mirrors the value operators plus `~` (class-of),
/// which the comparison layer doesn't carry because it resolves against the tree.
/// Bridges to a `SelectorOperator` for the value operators so the comparison build
/// is shared with the structural-selector parser.
enum PredicateOperatorToken: Equatable {
  case equal, notEqual, greater, less, greaterOrEqual, lessOrEqual
  case substring, matches, classOf

  /// The shared value operator, or `nil` for `~` (which the predicate layer
  /// handles itself, since it needs the tree).
  var selectorOperator: SelectorOperator? {
    switch self {
    case .equal: return .equal
    case .notEqual: return .notEqual
    case .greater: return .greater
    case .less: return .less
    case .greaterOrEqual: return .greaterOrEqual
    case .lessOrEqual: return .lessOrEqual
    case .substring: return .substring
    case .matches: return .matchesRegex
    case .classOf: return nil
    }
  }
}

// SPEC: domain.uitool.selector
/// Splits a `--where` source into `PredicateToken`s. A single left-to-right scan:
/// whitespace separates tokens, quotes bracket string literals, a fixed set of
/// punctuation forms the operators and grouping symbols, and `matches` (a word in
/// operator position) is recognized as the regex operator by the parser, not here.
enum PredicateLexer {
  private static let operatorTable: [(String, PredicateOperatorToken)] = [
    (">=", .greaterOrEqual), ("<=", .lessOrEqual), ("!=", .notEqual), ("*=", .substring),
    ("=", .equal), (">", .greater), ("<", .less), ("~", .classOf),
  ]

  /// Tokenize the whole source.
  static func tokenize(_ source: String) -> [PredicateToken] {
    let characters = Array(source)
    var tokens: [PredicateToken] = []
    var index = 0

    while index < characters.count {
      let character = characters[index]
      if character.isWhitespace {
        index += 1
      } else if character == "(" || character == ")" {
        tokens.append(.symbol(String(character)))
        index += 1
      } else if character == "\"" || character == "'" {
        tokens.append(.string(takeString(characters, &index, quote: character)))
      } else if let op = matchOperator(characters, &index) {
        tokens.append(.op(op))
      } else {
        tokens.append(wordToken(takeWord(characters, &index)))
      }
    }
    return tokens
  }

  /// `matches` is a word-shaped operator; recognize it as one so `text matches 'x'`
  /// lexes the same shape as `text *= 'x'`. Any other word stays a `.word`.
  private static func wordToken(_ word: String) -> PredicateToken {
    word.lowercased() == "matches" ? .op(.matches) : .word(word)
  }

  /// Consume a punctuation operator (longest token first), or `nil` if none starts
  /// here.
  private static func matchOperator(_ characters: [Character], _ index: inout Int)
    -> PredicateOperatorToken?
  {
    for (token, op) in operatorTable where startsWith(characters, at: index, token: token) {
      index += token.count
      return op
    }
    return nil
  }

  /// Consume a quoted run up to the closing quote (or end of input — an
  /// unterminated quote yields what was read; the parser still requires a literal,
  /// so a dangling quote becomes a benign token rather than a lexer throw).
  private static func takeString(_ characters: [Character], _ index: inout Int, quote: Character)
    -> String
  {
    index += 1
    var result = ""
    while index < characters.count, characters[index] != quote {
      result.append(characters[index])
      index += 1
    }
    if index < characters.count { index += 1 }
    return result
  }

  /// Consume a bareword: letters, digits, `_`, `-`, `.` — covers attribute paths
  /// (`frame-w`), numbers, class names, and keywords. Stops at whitespace, a quote,
  /// a paren, or the start of an operator.
  private static func takeWord(_ characters: [Character], _ index: inout Int) -> String {
    var result = ""
    while index < characters.count {
      let character = characters[index]
      if character.isWhitespace || "()\"'".contains(character) { break }
      if operatorStartsHere(characters, at: index) { break }
      result.append(character)
      index += 1
    }
    return result
  }

  /// `true` when a punctuation operator begins at `index` — the word scanner stops
  /// here so `frame-w>200` lexes as `frame-w`, `>`, `200` without spaces.
  private static func operatorStartsHere(_ characters: [Character], at index: Int) -> Bool {
    operatorTable.contains { startsWith(characters, at: index, token: $0.0) }
  }

  /// `true` when `token`'s characters appear starting at `index`.
  private static func startsWith(_ characters: [Character], at index: Int, token: String) -> Bool {
    let tokenCharacters = Array(token)
    guard index + tokenCharacters.count <= characters.count else { return false }
    return Array(characters[index..<index + tokenCharacters.count]) == tokenCharacters
  }
}
