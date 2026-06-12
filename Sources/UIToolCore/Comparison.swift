// SPEC: domain.uitool.selector
/// A single operator applied to a resolved attribute value — the leaf both an
/// `[attr op value]` selector predicate and a `--where` comparison reduce to. The
/// operator set is exactly [[domain.uitool.selector]]'s: `=`, `!=`, `>`, `<`,
/// `>=`, `<=`, `*=` (substring), `matches` (regex). The `~` class-of operator is
/// **not** here — it resolves against the runtime hierarchy through the tree, not
/// against a single value, so it lives in the selector/predicate layer.
///
/// Evaluation is **total**: every operator returns a `Bool` for every value with
/// no throw and no recursion. A type-mismatched comparison (a number op against a
/// string, an ordering op against a bool) is simply `false`, never an error — the
/// usage errors (bad pattern, unknown field) are caught at *parse* time, so
/// evaluation against the tree can never fail partway.
enum Comparison: Sendable {
  case equal(Operand)
  case notEqual(Operand)
  case greater(Double)
  case less(Double)
  case greaterOrEqual(Double)
  case lessOrEqual(Double)
  /// `*=` substring — a `Regex` over a literal-escaped needle, so it never throws.
  case substring(MatchEngine.Pattern)
  /// `matches` regex — the pattern compiled at parse time (a bad pattern is a
  /// `BAD_SELECTOR` rejected there, never here).
  case matches(MatchEngine.Pattern)

  /// Apply the operator to a node's attribute value. Total — see the type doc.
  func evaluate(_ value: AttributeValue) -> Bool {
    switch self {
    case .equal(let operand): return equals(value, operand)
    case .notEqual(let operand): return !equals(value, operand)
    case .greater(let rhs): return number(value).map { $0 > rhs } ?? false
    case .less(let rhs): return number(value).map { $0 < rhs } ?? false
    case .greaterOrEqual(let rhs): return number(value).map { $0 >= rhs } ?? false
    case .lessOrEqual(let rhs): return number(value).map { $0 <= rhs } ?? false
    case .substring(let pattern), .matches(let pattern):
      guard let string = value.asString else { return false }
      return pattern.matches(string)
    }
  }

  /// Equality across the three comparison domains. A string operand compares
  /// case-sensitively to a string value (`identifier = 'send'`); a number operand
  /// to a number value; a bool operand (`true`/`false`) to a bool value. `.absent`
  /// equals only the explicit empty-string operand is *not* a special case — an
  /// unset optional never equals a value, so `text = ''` does not match a null
  /// text (the spec's "distinct from an empty string").
  private func equals(_ value: AttributeValue, _ operand: Operand) -> Bool {
    switch (value.normalized, operand) {
    case (.string(let lhs), .text(let rhs)): return lhs == rhs
    case (.number(let lhs), .number(let rhs)): return lhs == rhs
    case (.bool(let lhs), .bool(let rhs)): return lhs == rhs
    // A bool value written as text, or a number value written as text, compares on
    // the node-printed form so `hidden = false` and `childCount = 3` work even when
    // the operand wasn't typed — the parser keeps the literal kind it saw.
    case (.bool(let lhs), .text(let rhs)): return (lhs ? "true" : "false") == rhs
    case (.number(let lhs), .text(let rhs)): return Predicate.printNumber(lhs) == rhs
    default: return false
    }
  }

  /// The numeric value for an ordering comparison, or `nil` for a non-numeric
  /// value (which makes the ordering `false`, never an error).
  private func number(_ value: AttributeValue) -> Double? {
    if case .number(let n) = value.normalized { return n }
    return nil
  }
}

// SPEC: domain.uitool.selector
/// A literal operand on the right of `=` / `!=` — the only operators whose operand
/// can be any of the three domains. Ordering and pattern operators carry their own
/// payloads (a `Double`, a `Pattern`), so they don't need this. The parser tags an
/// unquoted `true`/`false` as `.bool`, an unquoted number as `.number`, and
/// anything quoted (or otherwise) as `.text`.
enum Operand: Sendable, Equatable {
  case text(String)
  case number(Double)
  case bool(Bool)
}
