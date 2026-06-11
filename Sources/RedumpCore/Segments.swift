import Foundation
import MachOKit

// SPEC: command.redump.segments
/// One Mach-O segment, read straight from its load command — no disassembler.
/// `start`/`end` are the segment's unslid virtual-address range, hex-encoded
/// to match re-cli's `segments` shape. `type` is omitted: the native reader
/// has no clean source for re-cli's analyzer-derived segment classification.
public struct SegmentEntry: Encodable, Sendable {
  public let name: String
  public let start: String
  public let end: String
}

extension BinaryInspector {
  // SPEC: command.redump.segments
  /// Every segment of the primary (first) slice, in load order.
  public static func segments(path: String) throws -> [SegmentEntry] {
    let slices = try machOSlices(at: path)
    guard let primary = slices.first else { throw InspectError.unreadable(path) }
    return primary.segments.map { segment in
      let start = UInt64(segment.virtualMemoryAddress)
      let end = start + UInt64(segment.virtualMemorySize)
      return SegmentEntry(
        name: segment.segmentName,
        start: hex(start),
        end: hex(end)
      )
    }
  }

  static func hex(_ address: UInt64) -> String {
    "0x" + String(address, radix: 16)
  }
}
