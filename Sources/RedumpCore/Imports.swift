import Foundation
import MachOKit

// SPEC: command.redump.imports
/// One imported (undefined) symbol from a Mach-O: its name and, when the
/// two-level-namespace library ordinal resolves, the path of the dylib it is
/// expected to come from.
public struct ImportEntry: Encodable, Sendable {
  public let name: String
  public let library: String?
}

extension BinaryInspector {
  // SPEC: command.redump.imports
  /// Every imported (undefined) symbol in the primary (first) slice, read
  /// straight from the Mach-O symbol table via MachOKit — no disassembler. A
  /// symbol is imported when its nlist type is `N_UNDF` (undefined, no section).
  ///
  /// For two-level-namespace binaries each undefined symbol carries a library
  /// ordinal indexing the load command's dependent-dylib list; when it resolves
  /// to a real dependency that dylib's path is the symbol's `library`. Special
  /// ordinals (self / executable / dynamic-lookup / flat-namespace) do not name
  /// a specific dylib, so `library` is omitted for those symbols.
  ///
  /// `library`, when given, filters the result to imports whose resolved dylib
  /// path contains that substring; symbols with no resolved library are dropped.
  public static func imports(path: String, library: String? = nil) throws -> [ImportEntry] {
    let slices = try machOSlices(at: path)
    guard let primary = slices.first else { throw InspectError.unreadable(path) }

    let dependencies = primary.dependencies
    let entries = primary.symbols.compactMap { symbol -> ImportEntry? in
      guard symbol.nlist.flags?.type == .undf else { return nil }
      return ImportEntry(
        name: symbol.name,
        library: resolvedLibrary(for: symbol, dependencies: dependencies)
      )
    }

    guard let filter = library else { return entries }
    return entries.filter { $0.library?.contains(filter) ?? false }
  }

  /// Maps an undefined symbol's two-level-namespace library ordinal to the path
  /// of its source dylib, or `nil` when the ordinal is special or out of range.
  private static func resolvedLibrary(
    for symbol: some SymbolProtocol,
    dependencies: [DependedDylib]
  ) -> String? {
    guard let ordinal = symbol.nlist.symbolDescription?.libraryOrdinal else { return nil }
    let index = Int(ordinal) - 1
    guard dependencies.indices.contains(index) else { return nil }
    return dependencies[index].dylib.name
  }
}
