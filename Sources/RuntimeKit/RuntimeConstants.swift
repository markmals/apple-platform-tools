import Foundation

// SPEC: domain.runtime.type-encoding
/// Every Objective-C method/property type-encoding character, modeling FLEX's
/// `FLEXTypeEncoding` (`NS_ENUM(char, …)`). The raw value is the ASCII byte the
/// runtime emits for that type, so `TypeEncoding(rawValue:)` recognizes a byte
/// straight out of an `@encode(...)` string. Pure data: no `objc/runtime.h`,
/// no live runtime — recognizing an encoding is string recursion (see
/// `TypeEncodingParser`).
public enum TypeEncoding: Character, Sendable, CaseIterable {
  /// `\0` — the string terminator; never a real type.
  case null = "\0"
  /// `?` — unknown. Typically a function pointer, occasionally a nameless `{?=…}`.
  case unknown = "?"
  /// `c` — `char`.
  case char = "c"
  /// `i` — `int`.
  case int = "i"
  /// `s` — `short`.
  case short = "s"
  /// `l` — `long`.
  case long = "l"
  /// `q` — `long long`.
  case longLong = "q"
  /// `C` — `unsigned char`.
  case unsignedChar = "C"
  /// `I` — `unsigned int`.
  case unsignedInt = "I"
  /// `S` — `unsigned short`.
  case unsignedShort = "S"
  /// `L` — `unsigned long`.
  case unsignedLong = "L"
  /// `Q` — `unsigned long long`.
  case unsignedLongLong = "Q"
  /// `f` — `float`.
  case float = "f"
  /// `d` — `double`.
  case double = "d"
  /// `D` — `long double`.
  case longDouble = "D"
  /// `B` — C99 `_Bool` / ObjC `BOOL` on 64-bit.
  case cBool = "B"
  /// `v` — `void`.
  case void = "v"
  /// `*` — `char *` (C string).
  case cString = "*"
  /// `@` — an ObjC object (`id`), optionally followed by a quoted class name.
  case objcObject = "@"
  /// `#` — a `Class`.
  case objcClass = "#"
  /// `:` — a `SEL`.
  case selector = ":"
  /// `[` — opens an array, e.g. `[4i]`.
  case arrayBegin = "["
  /// `]` — closes an array.
  case arrayEnd = "]"
  /// `{` — opens a struct, e.g. `{CGPoint=dd}`.
  case structBegin = "{"
  /// `}` — closes a struct.
  case structEnd = "}"
  /// `(` — opens a union, e.g. `(?=II)`.
  case unionBegin = "("
  /// `)` — closes a union.
  case unionEnd = ")"
  /// `"` — quotes a struct member name or an object's class name.
  case quote = "\""
  /// `b` — a bitfield, e.g. `b8`. Unsupported: the encoding carries no alignment.
  case bitField = "b"
  /// `^` — a pointer to the following type, e.g. `^i`, `^{CGRect=…}`.
  case pointer = "^"
  /// `r` — the `const` qualifier prefix.
  case const = "r"
}

// SPEC: domain.runtime.type-encoding
/// Sizing constants the parser leans on, named rather than hard-coded so the
/// 64-bit assumptions (pointers, `id`, `Class`, `SEL` are all 8 bytes) read as
/// a deliberate contract. flexscope is arm64/x86_64-only, matching FLEX's
/// `sizeof(uintptr_t)` / `sizeof(id)` on the host.
public enum TypeEncodingSizes {
  /// The width of any pointer-shaped value: raw pointers, `id`, `Class`, `SEL`,
  /// `char *`, and the catch-all `?`. 8 on every supported (64-bit) target.
  public static let pointer = MemoryLayout<UnsafeRawPointer>.size
}
