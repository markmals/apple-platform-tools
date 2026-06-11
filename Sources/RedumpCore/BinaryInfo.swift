import Foundation
import MachOKit

// SPEC: command.redump.info
/// Native binary metadata read straight from the Mach-O — no disassembler.
/// (re-cli's `info` adds entry point + address range from IDA/Hopper analysis;
/// those fields require a disassembler backend and are out of scope for the
/// native reader.)
public struct BinaryInfo: Encodable, Sendable {
  public let path: String
  public let fileType: String
  public let archs: [String]
  public let bitness: Int
}

// SPEC: command.redump.info
/// Reads binary metadata directly from a Mach-O (thin or universal) using MachOKit.
public enum BinaryInspector {
  public enum InspectError: Error, CustomStringConvertible {
    case unreadable(String)
    public var description: String {
      switch self {
      case .unreadable(let path): return "redump: not a readable Mach-O: \(path)"
      }
    }
  }

  public static func info(path: String) throws -> BinaryInfo {
    let slices = try machOSlices(at: path)
    guard let primary = slices.first else { throw InspectError.unreadable(path) }
    return BinaryInfo(
      path: path,
      fileType: fileTypeName(primary.header.fileType),
      archs: slices.map { archName($0.header.cpuType) },
      bitness: is64Bit(primary.header.cpuType) ? 64 : 32
    )
  }

  /// Every Mach-O slice in the file — one for a thin binary, several for a universal one.
  static func machOSlices(at path: String) throws -> [MachOFile] {
    do {
      switch try loadFromFile(url: URL(fileURLWithPath: path)) {
      case .machO(let machO): return [machO]
      case .fat(let fat): return try fat.machOFiles()
      }
    } catch {
      throw InspectError.unreadable(path)
    }
  }

  static func archName(_ cpu: CPUType?) -> String {
    guard let cpu else { return "unknown" }
    switch cpu {
    case .arm64: return "arm64"
    case .arm64_32: return "arm64_32"
    case .arm: return "arm"
    case .x86_64: return "x86_64"
    case .x86, .i386: return "i386"
    case .powerpc: return "ppc"
    case .powerpc64: return "ppc64"
    default: return "\(cpu)"
    }
  }

  static func is64Bit(_ cpu: CPUType?) -> Bool {
    switch cpu {
    case .arm64, .x86_64, .powerpc64: return true
    default: return false
    }
  }

  static func fileTypeName(_ type: FileType?) -> String {
    guard let type else { return "unknown" }
    switch type {
    case .object: return "object"
    case .execute: return "execute"
    case .dylib: return "dylib"
    case .bundle: return "bundle"
    case .dylinker: return "dylinker"
    case .dylibStub: return "dylib-stub"
    case .dsym: return "dsym"
    case .kextBundle: return "kext"
    case .core: return "core"
    case .preload: return "preload"
    case .fileset: return "fileset"
    case .fvmlib: return "fvmlib"
    default: return "\(type)"
    }
  }
}
