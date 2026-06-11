import Foundation
import MachOKit

// SPEC: command.redump.exports
/// One exported symbol from a Mach-O's export trie: its name and, when the trie
/// records one, its offset from the start of the file as a hex string.
public struct ExportEntry: Encodable, Sendable {
  public let address: String?
  public let name: String
}

extension BinaryInspector {
  // SPEC: command.redump.exports
  /// Every exported symbol in the primary (first) slice, read straight from the
  /// Mach-O export trie via MachOKit — no disassembler. The address is the
  /// symbol's file offset as hex; it is omitted when the trie carries no offset
  /// (e.g. re-exports and absolute symbols).
  public static func exports(path: String) throws -> [ExportEntry] {
    let slices = try machOSlices(at: path)
    guard let primary = slices.first else { throw InspectError.unreadable(path) }
    return primary.exportedSymbols.map { symbol in
      ExportEntry(
        address: symbol.offset.map { String(format: "0x%llx", UInt64($0)) },
        name: symbol.name
      )
    }
  }
}
