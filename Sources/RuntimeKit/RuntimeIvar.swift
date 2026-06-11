import ObjectiveC

// SPEC: domain.runtime.reflection
/// The metadata of one Objective-C instance variable — a port of the reflection
/// half of FLEX's `FLEXIvar`. Reading an ivar's *shape*: its name, byte offset,
/// type encoding, and in-memory size. The value get/set machinery of `FLEXIvar`
/// (`getValue:`, `setValue:onObject:`, boxing, tagged-pointer handling) is out
/// of headless scope and is deliberately not ported.
public struct RuntimeIvar: Sendable {
  /// The ivar's name, e.g. `_count`. From `ivar_getName`.
  public let name: String
  /// The ivar's byte offset from the start of the instance. From `ivar_getOffset`.
  public let offset: Int
  /// The ivar's type encoding, e.g. `q`, `@"NSString"`, `{CGRect=…}`. From
  /// `ivar_getTypeEncoding`; `""` when the runtime has no type info for it.
  public let typeEncoding: String
  /// The ivar's in-memory size in bytes, from the pure `TypeEncodingParser`
  /// (FLEX sizes ivars with the same parser, not `NSGetSizeAndAlignment`). `0`
  /// when the type encoding is empty or the parser cannot size the type.
  public let size: Int

  /// Build the metadata for a single `Ivar` handle. The handle does not escape:
  /// every field is materialized into this value type here.
  init(_ ivar: Ivar) {
    self.name = ivar_getName(ivar).map { String(cString: $0) } ?? ""
    self.offset = ivar_getOffset(ivar)
    self.typeEncoding = ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? ""
    self.size = Self.size(ofTypeEncoding: self.typeEncoding)
  }

  /// Every instance variable the class **itself** declares (not inherited), in
  /// runtime-declaration order. Mirrors a `class_copyIvarList` walk; ivars whose
  /// handle the runtime cannot read are skipped.
  public static func ivars(of cls: AnyClass) -> [RuntimeIvar] {
    var count: UInt32 = 0
    guard let list = class_copyIvarList(cls, &count) else { return [] }
    defer { free(list) }
    let buffer = UnsafeBufferPointer(start: list, count: Int(count))
    return buffer.map(RuntimeIvar.init)
  }

  /// The parser-derived size, or `0` for an empty/unsizeable encoding — FLEX's
  /// "0 if unknown" contract, never a crash.
  private static func size(ofTypeEncoding encoding: String) -> Int {
    guard !encoding.isEmpty else { return 0 }
    return TypeEncodingParser.sizeAndAlignment(of: encoding)?.size ?? 0
  }
}
