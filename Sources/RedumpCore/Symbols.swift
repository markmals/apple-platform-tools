import Foundation
import MachOKit

// SPEC: command.redump.symbols
/// One entry from the Mach-O symbol table, read straight from the nlist — no
/// disassembler. `address` is the symbol's value (its `n_value`), hex-encoded.
/// `type` is a best-effort `function`/`data` classification derived from the
/// symbol's defining section (text/code section → `function`); it is `nil` for
/// symbols with no defining section (undefined, absolute), which the native
/// reader cannot classify.
public struct SymbolEntry: Encodable, Sendable {
  public let address: String
  public let name: String
  public let type: String?
}

// SPEC: command.redump.symbols
/// Bad user input to `redump symbols` — an unrecognized `--type` value or an
/// `--filter` that is not a valid regular expression. Distinct from
/// `BinaryInspector.InspectError`, which covers an unreadable Mach-O.
public enum SymbolQueryError: Error, CustomStringConvertible {
  case invalidType(String)
  case invalidFilter(String)

  public var description: String {
    switch self {
    case .invalidType(let value):
      return "redump: --type must be function, data, or all (got: \(value))"
    case .invalidFilter(let pattern):
      return "redump: --filter is not a valid regular expression: \(pattern)"
    }
  }
}

extension BinaryInspector {
  // SPEC: command.redump.symbols
  /// The symbol table of the primary (first) slice, in table order.
  ///
  /// - `filter` is an `NSRegularExpression` matched against each symbol's `name`;
  ///   a symbol is kept when the pattern matches anywhere in the name.
  /// - `type` narrows by classification: `function` (defined in a code section),
  ///   `data` (everything else), or `all` (the default — no narrowing).
  public static func symbols(
    path: String,
    filter: String? = nil,
    type: String? = nil
  ) throws -> [SymbolEntry] {
    let slices = try machOSlices(at: path)
    guard let primary = slices.first else { throw InspectError.unreadable(path) }

    let regex = try compileFilter(filter)
    let kind = try parseTypeFilter(type)
    let codeSections = codeSectionNumbers(of: primary)

    var entries: [SymbolEntry] = []
    for symbol in primary.symbols {
      let classification = symbolType(of: symbol, codeSections: codeSections)
      guard kind.admits(classification) else { continue }
      guard matches(regex, symbol.name) else { continue }
      entries.append(
        SymbolEntry(
          address: hex(UInt64(bitPattern: Int64(symbol.offset))),
          name: symbol.name,
          type: classification
        )
      )
    }
    return entries
  }

  // MARK: - Classification

  /// 1-based section numbers (as `nlist.sectionNumber` reports them) whose
  /// section carries machine instructions — `__text` and friends. A symbol
  /// defined in one of these is a function; anything else defined in a section
  /// is data.
  static func codeSectionNumbers(of machO: MachOFile) -> Set<Int> {
    var result: Set<Int> = []
    for (index, section) in machO.sections.enumerated() where isCodeSection(section) {
      result.insert(index + 1)
    }
    return result
  }

  static func isCodeSection(_ section: any SectionProtocol) -> Bool {
    let attributes = section.flags.attributes
    if attributes.contains(.pure_instructions) || attributes.contains(.some_instructions) {
      return true
    }
    return section.segmentName == "__TEXT" && section.sectionName == "__text"
  }

  /// `"function"` when the symbol is defined in a code section, `"data"` when
  /// it is defined in some other section, `nil` when it has no defining section.
  static func symbolType(of symbol: MachOFile.Symbol, codeSections: Set<Int>) -> String? {
    guard symbol.nlist.flags?.type == .sect, let section = symbol.nlist.sectionNumber else {
      return nil
    }
    return codeSections.contains(section) ? "function" : "data"
  }

  // MARK: - Filters

  enum TypeFilter {
    case all
    case function
    case data

    func admits(_ symbolType: String?) -> Bool {
      switch self {
      case .all: return true
      case .function: return symbolType == "function"
      case .data: return symbolType != "function"
      }
    }
  }

  static func parseTypeFilter(_ type: String?) throws -> TypeFilter {
    switch type {
    case nil, "all": return .all
    case "function": return .function
    case "data": return .data
    default: throw SymbolQueryError.invalidType(type ?? "")
    }
  }

  static func compileFilter(_ pattern: String?) throws -> NSRegularExpression? {
    guard let pattern else { return nil }
    do {
      return try NSRegularExpression(pattern: pattern)
    } catch {
      throw SymbolQueryError.invalidFilter(pattern)
    }
  }

  static func matches(_ regex: NSRegularExpression?, _ name: String) -> Bool {
    guard let regex else { return true }
    let range = NSRange(name.startIndex..., in: name)
    return regex.firstMatch(in: name, range: range) != nil
  }
}
