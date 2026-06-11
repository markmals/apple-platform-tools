import Foundation

// SPEC: domain.runtime.type-encoding
/// A pure-Swift port of FLEX's `FLEXTypeEncodingParser` — the size/alignment and
/// method-signature sanitizer for Objective-C type encodings, with **no**
/// `objc/runtime.h` and no live runtime. Parsing a type encoding is string
/// recursion over structs, unions, arrays, and pointers; this is the recursion.
///
/// Two jobs:
/// 1. **Sizing** — `sizeAndAlignment(of:)` computes the in-memory `(size, alignment)`
///    of a type without calling `NSGetSizeAndAlignment`, returning `nil` for forms
///    the runtime can't size (bitfields outside structs, malformed encodings).
/// 2. **Sanitizing** — `cleaned(_:)` / `methodSignatureSupported(_:)` strip the
///    forms `NSMethodSignature` chokes on (unions, unsupported pointer-to-struct,
///    nameless C++ structs) so a "cleaned" encoding can be handed to the runtime
///    without provoking an `objc_exception_throw`.
public enum TypeEncodingParser {
  /// The in-memory size and alignment of a single type encoding, or `nil` if the
  /// type is unsupported. Mirrors FLEX's `+sizeForTypeEncoding:alignment:` (which
  /// defaults to the *aligned* size).
  ///
  /// Do **not** pass a full method type encoding (return type + argument frame);
  /// pass the encoding of one type. The size for supported scalars, pointers,
  /// structs, unions, and arrays agrees with `NSGetSizeAndAlignment`.
  public static func sizeAndAlignment(of encoding: String) -> (size: Int, alignment: Int)? {
    var alignment = 0
    let size = self.size(ofTypeEncoding: encoding, alignment: &alignment, unaligned: false)
    if size == -1 {
      return nil
    }
    return (size, alignment)
  }

  /// The size in bytes of a type encoding, or `-1` if unsupported. `unaligned`
  /// requests the raw member-sum size rather than the alignment-padded size.
  /// Mirrors FLEX's `+sizeForTypeEncoding:alignment:unaligned:`.
  public static func size(
    ofTypeEncoding type: String,
    alignment alignOut: inout Int,
    unaligned: Bool
  ) -> Int {
    let info = Scanner(type).parseType()

    var size = info.size
    let align = info.align

    if info.supported {
      alignOut = align
      if !unaligned {
        // Faithful to FLEX: the aligned size is `size + (size % align)`,
        // not a round-up-to-multiple. The oracle (NSGetSizeAndAlignment)
        // was matched against exactly this arithmetic.
        if align != 0 {
          size += size % align
        }
      }
    }

    // size is -1 if not supported.
    return size
  }

  /// Whether `encoding` — a full method type encoding (return type followed by the
  /// argument frame) — can be handed to `NSMethodSignature` without it throwing.
  /// Mirrors FLEX's `+methodTypeEncodingSupported:cleaned:` with `cleaned:nil`.
  public static func methodSignatureSupported(_ encoding: String) -> Bool {
    var ignored: String?
    return methodSignatureSupported(encoding, cleaned: &ignored)
  }

  /// The "safe" rewrite of a method type encoding: unions, unsupported
  /// pointer-to-struct, and nameless C++ structs replaced with forms
  /// `NSMethodSignature` accepts (`{Name=}`, `^?`, …). Returns `nil` when the
  /// encoding is unsupported even after cleaning. Mirrors the `cleanedEncoding`
  /// out-parameter of FLEX's `+methodTypeEncodingSupported:cleaned:`.
  public static func cleaned(_ encoding: String) -> String? {
    var out: String?
    return methodSignatureSupported(encoding, cleaned: &out) ? out : nil
  }

  /// The shared body behind `methodSignatureSupported(_:)` and `cleaned(_:)`:
  /// scan every type in the frame, reject on any unsupported / union / zero-size
  /// non-void member, and surface the accumulated `cleaned` string on success.
  private static func methodSignatureSupported(_ encoding: String, cleaned: inout String?) -> Bool {
    guard !encoding.isEmpty else {
      return false
    }

    let scanner = Scanner(encoding)

    while !scanner.isAtEnd {
      let info = scanner.parseNextType()
      if !info.supported || info.containsUnion || (info.size == 0 && !info.isVoid) {
        return false
      }
    }

    cleaned = scanner.cleanedString
    return true
  }
}

// SPEC: domain.runtime.type-encoding
/// Per-type result of one `parseNextType` step. Faithful to FLEX's `FLEXTypeInfo`.
private struct TypeInfo {
  /// The unaligned size, or `-1` if the type is not supported at all.
  var size: Int
  /// The type's alignment.
  var align: Int
  /// `false` only if the type cannot be supported at all; `true` if it is
  /// fully or partially supported.
  var supported: Bool
  /// `true` if the type was only partially supported and was patched — e.g. a
  /// union inside a pointer, or a named struct with no member info. These can be
  /// corrected with less information rather than dropped.
  var fixesApplied: Bool
  /// `true` if this type is a union or (recursively, excluding pointers) contains
  /// one. Unions are sizeable by `NSGetSizeAndAlignment` but rejected by
  /// `NSMethodSignature`, so they must be tracked to clean them out of pointers.
  var containsUnion: Bool
  /// `size == 0` is only valid when this is the void type.
  var isVoid: Bool

  /// A completely unsupported type.
  static let unsupported = TypeInfo(
    size: -1, align: 0, supported: false, fixesApplied: false, containsUnion: false, isVoid: false)

  /// The void return type.
  static let void = TypeInfo(
    size: 0, align: 0, supported: true, fixesApplied: false, containsUnion: false, isVoid: true)

  /// A fully or partially supported type.
  static func make(size: Int, align: Int, fixed: Bool) -> TypeInfo {
    TypeInfo(
      size: size, align: align, supported: true, fixesApplied: fixed, containsUnion: false,
      isVoid: false)
  }

  /// A fully or partially supported type, recording whether it carries a union.
  static func make(size: Int, align: Int, fixed: Bool, hasUnion: Bool) -> TypeInfo {
    TypeInfo(
      size: size, align: align, supported: true, fixesApplied: fixed, containsUnion: hasUnion,
      isVoid: false)
  }
}

// SPEC: domain.runtime.type-encoding
/// The recursive-descent scanner over a single encoding string, ported from the
/// `NSScanner`-backed `FLEXTypeEncodingParser` instance. Operates on a
/// `[Character]` buffer with an integer cursor; `cleaned` is a parallel buffer
/// edited in place as unsupported pointer-types are sanitized.
private final class Scanner {
  /// The encoding being parsed.
  private let chars: [Character]
  /// The cursor into `chars`. Named `scanLocation` to match FLEX.
  private var scanLocation: Int = 0
  /// The working sanitized copy; replacements land here as we scan.
  private var cleaned: [Character]

  init(_ string: String) {
    self.chars = Array(string)
    self.cleaned = self.chars
  }

  var isAtEnd: Bool { scanLocation >= chars.count }

  var cleanedString: String { String(cleaned) }

  /// The substring not yet scanned — FLEX's `unscanned`.
  private var unscanned: String { String(chars[scanLocation...]) }

  /// The character at the cursor. Precondition: not at end (matches FLEX, which
  /// indexes unconditionally; callers guard with `isAtEnd` / a known opener).
  private var nextChar: Character { chars[scanLocation] }

  // MARK: - Character set helpers

  /// First character of a struct/class identifier: a letter, `_`, or `$`.
  private func isIdentifierFirst(_ c: Character) -> Bool {
    c == "_" || c == "$" || (c.isASCII && c.isLetter)
  }

  /// Subsequent identifier characters: identifier-first plus digits.
  private func isIdentifier(_ c: Character) -> Bool {
    isIdentifierFirst(c) || (c.isASCII && c.isNumber)
  }

  // MARK: - Low-level scanning

  /// Whether the cursor sits on `c` without consuming it. FLEX's `canScanChar:`.
  private func canScanChar(_ c: Character) -> Bool {
    guard scanLocation < chars.count else { return false }
    return chars[scanLocation] == c
  }

  /// Consume `c` if present. FLEX's `scanChar:`.
  @discardableResult
  private func scanChar(_ c: Character) -> Bool {
    if canScanChar(c) {
      scanLocation += 1
      return true
    }
    return false
  }

  /// Consume the encoding `e` if present.
  @discardableResult
  private func scanChar(_ e: TypeEncoding) -> Bool {
    scanChar(e.rawValue)
  }

  private func canScanChar(_ e: TypeEncoding) -> Bool {
    canScanChar(e.rawValue)
  }

  /// Consume the literal string `str` if the cursor sits on it. FLEX's `scanString:`.
  @discardableResult
  private func scanString(_ str: String) -> Bool {
    let needle = Array(str)
    guard scanLocation + needle.count <= chars.count else { return false }
    for (i, ch) in needle.enumerated() where chars[scanLocation + i] != ch {
      return false
    }
    scanLocation += needle.count
    return true
  }

  /// Consume an optional `[+-]?[0-9]+` and return its value, or `0` without
  /// advancing if there are no digits. Mirrors `NSScanner.scanInteger`.
  @discardableResult
  private func scanSize() -> Int {
    let start = scanLocation
    var sign = 1
    if scanLocation < chars.count, chars[scanLocation] == "-" || chars[scanLocation] == "+" {
      if chars[scanLocation] == "-" { sign = -1 }
      scanLocation += 1
    }

    var digits = ""
    while scanLocation < chars.count, chars[scanLocation].isASCII, chars[scanLocation].isNumber {
      digits.append(chars[scanLocation])
      scanLocation += 1
    }

    if digits.isEmpty {
      scanLocation = start
      return 0
    }

    return sign * (Int(digits) ?? 0)
  }

  /// Scan a balanced `c1 … c2` pair (nesting-aware) and return the slice scanned,
  /// or `nil` if there is no matching close. FLEX's `scanPair:close:`.
  @discardableResult
  private func scanPair(open c1: Character, close c2: Character) -> String? {
    let start = scanLocation

    guard scanChar(c1) else {
      scanLocation = start
      return nil
    }

    var depth = 1
    while scanLocation < chars.count {
      let c = chars[scanLocation]
      if c == c2 {
        scanLocation += 1
        depth -= 1
        if depth == 0 { break }
        continue
      }
      if c == c1 {
        scanLocation += 1
        depth += 1
        continue
      }
      scanLocation += 1
    }

    if depth != 0 {
      scanLocation = start
      return nil
    }

    return String(chars[start..<scanLocation])
  }

  private func scanPair(open o: TypeEncoding, close c: TypeEncoding) -> String? {
    scanPair(open: o.rawValue, close: c.rawValue)
  }

  /// Scan a struct/class identifier (`abc`, `_Foo`, `$bar9`), or `nil`.
  private func scanIdentifier() -> String? {
    guard scanLocation < chars.count, isIdentifierFirst(chars[scanLocation]) else {
      return nil
    }
    let start = scanLocation
    while scanLocation < chars.count, isIdentifier(chars[scanLocation]) {
      scanLocation += 1
    }
    return String(chars[start..<scanLocation])
  }

  /// The byte distance the cleaned string has shrunk so far, so further
  /// replacements land at the right offset. FLEX's `cleanedReplacingOffset`.
  private var cleanedReplacingOffset: Int { chars.count - cleaned.count }

  // MARK: - Size table

  /// The size in bytes of a scalar/pointer encoding, or `-1`. FLEX's `sizeForType:`.
  private func size(forType type: TypeEncoding) -> Int {
    switch type {
    case .char: return MemoryLayout<CChar>.size
    case .int: return MemoryLayout<CInt>.size
    case .short: return MemoryLayout<CShort>.size
    case .long: return MemoryLayout<CLong>.size
    case .longLong: return MemoryLayout<CLongLong>.size
    case .unsignedChar: return MemoryLayout<CUnsignedChar>.size
    case .unsignedInt: return MemoryLayout<CUnsignedInt>.size
    case .unsignedShort: return MemoryLayout<CUnsignedShort>.size
    case .unsignedLong: return MemoryLayout<CUnsignedLong>.size
    case .unsignedLongLong: return MemoryLayout<CUnsignedLongLong>.size
    case .float: return MemoryLayout<CFloat>.size
    case .double: return MemoryLayout<CDouble>.size
    case .longDouble: return MemoryLayout<CLongDouble>.size
    case .cBool: return MemoryLayout<CBool>.size
    case .void: return 0
    case .cString: return TypeEncodingSizes.pointer
    case .objcObject: return TypeEncodingSizes.pointer
    case .objcClass: return TypeEncodingSizes.pointer
    case .selector: return TypeEncodingSizes.pointer
    // `?` is typically a pointer (a function pointer). In the rare case it is
    // not — e.g. the `{?=…}` of a nameless struct — it is never passed here.
    case .unknown, .pointer: return TypeEncodingSizes.pointer
    default: return -1
    }
  }

  // MARK: - parseType entry points

  /// Parse the whole encoding as one type and return its info. FLEX's
  /// `+parseType:`.
  func parseType() -> TypeInfo {
    parseNextType()
  }

  // MARK: - parseNextType

  /// Parse the type at the cursor, advancing past it. The heart of the parser —
  /// a faithful port of `-parseNextType`.
  func parseNextType() -> TypeInfo {
    let start = scanLocation

    // Check for void first.
    if scanChar(.void) {
      // Skip the argument frame offset for method signatures.
      scanSize()
      return .void
    }

    // Scan optional const.
    scanChar(.const)

    // Pointer: recurse to scan the pointee.
    if scanChar(.pointer) {
      let pointerTypeStart = scanLocation
      if scanPastArg() {
        let pointerTypeLength = scanLocation - pointerTypeStart
        let pointerType = String(chars[pointerTypeStart..<scanLocation])

        // Deeply nested cleaning info is lost here, matching FLEX.
        let (info, nestedCleaned) = Scanner.parseType(pointerType)
        var cleanedPointee = nestedCleaned
        let needsCleaning = !info.supported || info.containsUnion || info.fixesApplied

        // Clean the pointee if it is unsupported, malformed, or contains a union.
        // (Unions are sizeable by NSGetSizeAndAlignment but rejected by
        // NSMethodSignature.)
        if needsCleaning {
          // If unsupported, parseType above did no cleaning. If partially
          // supported, reuse its cleaned form. Otherwise re-derive a clean
          // pointee in place.
          if !info.supported || info.containsUnion {
            cleanedPointee = cleanPointeeType(at: pointerTypeStart)
          }

          let offset = cleanedReplacingOffset
          let location = pointerTypeStart - offset
          replaceCleaned(
            location: location, length: pointerTypeLength, with: cleanedPointee)
        }

        // Skip optional frame offset.
        scanSize()

        let size = self.size(forType: .pointer)
        return .make(size: size, align: size, fixed: !info.supported || info.fixesApplied)
      } else {
        scanLocation = start
        return .unsupported
      }
    }

    // Struct / union / array.
    let next = nextCharOrNull()
    var didScanSUA = true
    var structOrUnion = false
    var isUnion = false
    var opening: TypeEncoding = .null
    var closing: TypeEncoding = .null
    switch next {
    case .structBegin:
      structOrUnion = true
      opening = .structBegin
      closing = .structEnd
    case .unionBegin:
      structOrUnion = true
      isUnion = true
      opening = .unionBegin
      closing = .unionEnd
    case .arrayBegin:
      opening = .arrayBegin
      closing = .arrayEnd
    default:
      didScanSUA = false
    }

    if didScanSUA {
      return parseStructUnionArray(
        start: start, opening: opening, closing: closing, structOrUnion: structOrUnion,
        isUnion: isUnion)
    }

    // A single scalar / object plus an optional size.
    return parseScalar(start: start)
  }

  /// The struct/union/array branch of `parseNextType`.
  private func parseStructUnionArray(
    start: Int, opening: TypeEncoding, closing: TypeEncoding, structOrUnion: Bool, isUnion: Bool
  ) -> TypeInfo {
    var containsUnion = isUnion
    var fixesApplied = false

    let backup = scanLocation

    // Ensure there is a matching close.
    guard scanPair(open: opening, close: closing) != nil else {
      scanLocation = start
      return .unsupported
    }

    // Move just past the opening tag.
    var arrayCount = -1
    scanLocation = backup + 1

    if !structOrUnion {
      arrayCount = scanSize()
      if arrayCount == 0 || canScanChar(.arrayEnd) {
        // Malformed array: a count must follow the brace, and an element
        // type must follow the count.
        scanLocation = start
        return .unsupported
      }
    } else {
      // Skip the `?=`/`Name=` portion of e.g. `{?=b8b4…}`. Optional; if it
      // fails we stay put — unless we're at `{?}`, which is invalid.
      if !scanTypeName() && canScanChar(.unknown) {
        scanLocation = start
        return .unsupported
      }
    }

    var sizeSoFar = 0
    var maxAlign = 0
    let cleanedBackup = cleaned

    while !scanChar(closing) {
      let member = nextCharOrNull()

      // Bitfields cannot be supported: their encoding carries no alignment.
      if member == .bitField {
        scanLocation = start
        return .unsupported
      }

      // Struct fields may be named: `"name"<type>`.
      if member == .quote {
        _ = scanPair(open: .quote, close: .quote)
      }

      let info = parseNextType()
      if !info.supported || info.containsUnion {
        // parseNextType above is the only call that can mutate `cleaned`
        // recursively, so this is the only place we must rewind it: if we
        // cleaned a few pointer members and then hit an unsupported member,
        // the parent call needs to wipe the whole structure, so undo our
        // partial edits first.
        cleaned = cleanedBackup
        scanLocation = start
        return .unsupported
      }

      // Unions are the size of their largest member; arrays are element ×
      // count; structs are the sum of members.
      if structOrUnion {
        if isUnion {
          sizeSoFar = max(sizeSoFar, info.size)
        } else {
          sizeSoFar += info.size
        }
      } else {
        sizeSoFar = info.size * arrayCount
      }

      maxAlign = max(maxAlign, info.align)
      containsUnion = containsUnion || info.containsUnion
      fixesApplied = fixesApplied || info.fixesApplied
    }

    // Skip optional frame offset.
    scanSize()

    return .make(size: sizeSoFar, align: maxAlign, fixed: fixesApplied, hasUnion: containsUnion)
  }

  /// The single-scalar/object branch of `parseNextType`.
  private func parseScalar(start: Int) -> TypeInfo {
    var size = -1
    guard let t = TypeEncoding(rawValue: nextCharOrPlaceholder()) else {
      scanLocation = start
      return .unsupported
    }

    switch t {
    case .unknown, .char, .int, .short, .long, .longLong, .unsignedChar, .unsignedInt,
      .unsignedShort, .unsignedLong, .unsignedLongLong, .float, .double, .longDouble, .cBool,
      .cString, .selector, .bitField:
      scanLocation += 1
      scanSize()
      if t == .bitField {
        scanLocation = start
        return .unsupported
      }
      size = self.size(forType: t)

    case .objcObject, .objcClass:
      scanLocation += 1
      // These may carry a number OR a quoted class name.
      scanSize()
      _ = scanPair(open: .quote, close: .quote)
      size = TypeEncodingSizes.pointer

    default:
      break
    }

    if size > 0 {
      // A scalar's alignment is its size.
      return .make(size: size, align: size, fixed: false)
    }

    scanLocation = start
    return .unsupported
  }

  // MARK: - scanPastArg

  /// Scan past one whole type without computing its size. FLEX's `-scanPastArg`.
  @discardableResult
  func scanPastArg() -> Bool {
    let start = scanLocation

    if scanChar(.void) {
      return true
    }

    scanChar(.const)

    if scanChar(.pointer) {
      if scanPastArg() {
        return true
      } else {
        scanLocation = start
        return false
      }
    }

    let next = nextCharOrNull()

    var opening: TypeEncoding = .null
    var closing: TypeEncoding = .null
    var checkPair = true
    switch next {
    case .structBegin:
      opening = .structBegin
      closing = .structEnd
    case .unionBegin:
      opening = .unionBegin
      closing = .unionEnd
    case .arrayBegin:
      opening = .arrayBegin
      closing = .arrayEnd
    default:
      checkPair = false
    }

    if checkPair, scanPair(open: opening, close: closing) != nil {
      return true
    }

    switch next {
    case .unknown, .char, .int, .short, .long, .longLong, .unsignedChar, .unsignedInt,
      .unsignedShort, .unsignedLong, .unsignedLongLong, .float, .double, .longDouble, .cBool,
      .cString, .selector, .bitField:
      scanLocation += 1
      scanSize()
      return true

    case .objcObject, .objcClass:
      scanLocation += 1
      // These may carry a number OR a quoted class name.
      if scanSize() == 0 {
        _ = scanPair(open: .quote, close: .quote)
      }
      return true

    default:
      break
    }

    scanLocation = start
    return false
  }

  // MARK: - Type-name scanning

  /// Skip the `?=`/`Name=` prefix of a struct/union body. FLEX's `-scanTypeName`.
  private func scanTypeName() -> Bool {
    let start = scanLocation

    // The `?=` of e.g. `{?=b8b4b1b1b18[8S]}`.
    if scanChar(.unknown) {
      if !scanString("=") {
        // No size info for strings like `{?=}` with nothing after.
        scanLocation = start
        return false
      }
    } else {
      if scanIdentifier() == nil || !scanString("=") {
        // Not a valid identifier, or no member info (e.g. `{CGPoint}`).
        scanLocation = start
        return false
      }
    }

    return true
  }

  /// Extract a struct/union's type name from the cursor, optionally tolerating a
  /// missing `=…` body. FLEX's `-extractTypeNameFromScanLocation:closing:`.
  private func extractTypeName(allowMissingTypeInfo: Bool, closing closeTag: TypeEncoding)
    -> String?
  {
    let start = scanLocation

    if scanChar(.unknown) {
      return "?"
    }

    guard let typeName = scanIdentifier() else {
      scanLocation = start
      return nil
    }

    let next = nextCharOrPlaceholder()
    if next == "=" {
      return typeName
    }

    // `=` is required unless we allow missing info and the next char closes.
    if allowMissingTypeInfo, next == closeTag.rawValue {
      return typeName
    }

    // Possibly a generic C++ type, e.g. `{pair<T, U>}`.
    scanLocation = start
    return nil
  }

  // MARK: - Cleaning

  /// Produce a sanitized form of the pointee type starting at `scanLocation`,
  /// without changing the cursor on return. FLEX's `-cleanPointeeTypeAtLocation:`.
  private func cleanPointeeType(at location: Int) -> String {
    let start = scanLocation
    scanLocation = location

    // Return the verbatim slice when the scanned type is already clean.
    let typeIsClean: () -> String = { [self] in
      let clean = String(chars[location..<scanLocation])
      scanLocation = start
      return clean
    }

    // No void: this is not a return type.

    // Scan optional const.
    scanChar(.const)

    let next = nextCharOrNull()
    switch next {
    case .pointer:
      scanChar(.pointer)
      return cleanPointeeType(at: scanLocation)

    case .arrayBegin:
      // All arrays are supported; scan past them.
      if scanPair(open: .arrayBegin, close: .arrayEnd) != nil {
        return typeIsClean()
      }

    case .unionBegin:
      // Unions are not supported at all by NSMethodSignature.
      scanLocation = start
      return "?"

    case .structBegin:
      let info = Scanner(unscanned).parseType()
      if info.supported && !info.fixesApplied {
        scanPastArg()
        return typeIsClean()
      }

      // The struct is unsupported: return its name if it has one, else `?`.
      scanLocation += 1  // Skip past `{`.
      let name = extractTypeName(allowMissingTypeInfo: true, closing: .structEnd)
      if let name {
        // Scan past the closing token.
        scanUpToString("}")
        if !scanChar(.structEnd) {
          scanLocation = start
          return ""  // FLEX returns nil; an empty rewrite is the safe analogue.
        }
        scanLocation = start
        return "{" + name + "=}"
      } else {
        // Not a valid identifier — possibly a C++ type.
        scanLocation = start
        return "{?=}"
      }

    default:
      break
    }

    // Other types are, in theory, all valid.
    let info = parseNextType()
    if info.supported && !info.fixesApplied {
      return typeIsClean()
    }

    scanLocation = start
    return "?"
  }

  /// Scan forward until (but not past) the first occurrence of `str`.
  private func scanUpToString(_ str: String) {
    let needle = Array(str)
    guard !needle.isEmpty else { return }
    while scanLocation < chars.count {
      if scanLocation + needle.count <= chars.count {
        var matched = true
        for (i, ch) in needle.enumerated() where chars[scanLocation + i] != ch {
          matched = false
          break
        }
        if matched { return }
      }
      scanLocation += 1
    }
  }

  /// Splice `replacement` into the cleaned buffer over `length` characters at
  /// `location`. FLEX's `replaceCharactersInRange:withString:` on `self.cleaned`.
  private func replaceCleaned(location: Int, length: Int, with replacement: String) {
    let end = location + length
    cleaned.replaceSubrange(location..<end, with: Array(replacement))
  }

  // MARK: - Cursor helpers

  /// The char at the cursor, or `.null` at end — for the SUA dispatch that
  /// reads `nextChar` after a guard, where FLEX would already be in bounds.
  private func nextCharOrNull() -> TypeEncoding {
    guard scanLocation < chars.count else { return .null }
    return TypeEncoding(rawValue: chars[scanLocation]) ?? .null
  }

  /// The raw char at the cursor, or `\0` at end.
  private func nextCharOrPlaceholder() -> Character {
    guard scanLocation < chars.count else { return "\0" }
    return chars[scanLocation]
  }

  // MARK: - Static parseType

  /// Parse `type` and return its info plus the cleaned string. FLEX's
  /// `+parseType:cleaned:`.
  private static func parseType(_ type: String) -> (info: TypeInfo, cleaned: String) {
    let scanner = Scanner(type)
    let info = scanner.parseNextType()
    return (info, scanner.cleanedString)
  }
}
