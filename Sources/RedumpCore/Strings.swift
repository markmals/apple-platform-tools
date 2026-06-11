import Foundation
import MachOKit

// SPEC: command.redump.strings
/// One C string read straight from the Mach-O's `__TEXT,__cstring` section: its
/// value and the virtual address it lives at, hex-encoded. The address is the
/// section's unslid `vmaddr` plus the string's offset within the section.
public struct StringEntry: Encodable, Sendable {
  public let address: String
  public let value: String
}

extension BinaryInspector {
  // SPEC: command.redump.strings
  /// Every NUL-terminated C string in the primary (first) slice's `__TEXT,__cstring`
  /// section, read straight from the Mach-O via MachOKit — no disassembler.
  ///
  /// MachOKit's `cStrings` sequence walks the section and splits it on NUL; each
  /// entry carries its offset *within the section*, which we add to the section's
  /// `vmaddr` to recover the string's virtual address.
  ///
  /// - `minLength` drops strings shorter than that many characters.
  /// - `filter` is an `NSRegularExpression` matched against each value, with the
  ///   same semantics as `redump symbols` (kept when the pattern matches anywhere).
  public static func strings(
    path: String,
    minLength: Int = 4,
    filter: String? = nil
  ) throws -> [StringEntry] {
    let slices = try machOSlices(at: path)
    guard let primary = slices.first else { throw InspectError.unreadable(path) }

    let regex = try compileFilter(filter)

    guard let sectionAddress = cstringSectionAddress(in: primary), let table = primary.cStrings
    else {
      return []
    }

    return table.compactMap { entry in
      let value = entry.string
      guard value.count >= minLength, matches(regex, value) else { return nil }
      return StringEntry(
        address: hex(sectionAddress + UInt64(entry.offset)),
        value: value
      )
    }
  }

  /// The unslid virtual address of the primary slice's `__TEXT,__cstring` section,
  /// or `nil` when the slice has no such section.
  static func cstringSectionAddress(in machO: MachOFile) -> UInt64? {
    machO.sections.first {
      $0.segmentName == "__TEXT" && $0.sectionName == "__cstring"
    }
    .map { UInt64($0.address) }
  }
}
