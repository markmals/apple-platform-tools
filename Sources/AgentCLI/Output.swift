import Foundation

// SPEC: domain.agent-cli
/// The deterministic JSON projection every tool's stdout obeys. Pure: the
/// `json`/`line` functions return strings and are unit-testable on any Mac;
/// `emit`/`emitLines` are the stdout edge.
public enum Output {
  /// A pretty-printed, key-sorted, slash-unescaped JSON string for a scalar result.
  public static func json(_ value: some Encodable) throws -> String {
    try encode(value, pretty: true)
  }

  /// A compact, single-line, key-sorted JSON string — one record in a JSON-Lines stream.
  public static func line(_ value: some Encodable) throws -> String {
    try encode(value, pretty: false)
  }

  /// Print a scalar result to stdout. The machine payload — and only the payload — lands here.
  public static func emit(_ value: some Encodable) throws {
    print(try json(value))
  }

  /// Print a JSON-Lines stream to stdout: one compact object per line, in order.
  public static func emitLines(_ values: [some Encodable]) throws {
    for value in values { print(try line(value)) }
  }

  private static func encode(_ value: some Encodable, pretty: Bool) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting =
      pretty
      ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      : [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

// SPEC: domain.agent-cli
/// Round a float to a fixed number of decimal places so equal results encode to
/// byte-identical bytes regardless of accumulated floating-point error.
public func stableRounded(_ value: Double, places: Int = 3) -> Double {
  let factor = pow(10.0, Double(places))
  return (value * factor).rounded() / factor
}
