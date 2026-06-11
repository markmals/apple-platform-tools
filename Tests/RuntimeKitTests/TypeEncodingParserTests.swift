import Foundation
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.type-encoding
@Suite(.spec("domain.runtime.type-encoding"))
struct TypeEncodingParserTests {

  /// The oracle: `NSGetSizeAndAlignment` itself. Only call on **supported**
  /// encodings — the runtime throws an ObjC exception on unsupported ones, which
  /// Swift cannot catch, so unsupported forms are asserted against the parser
  /// directly (never the oracle).
  private static func runtimeSizeAndAlignment(_ encoding: String) -> (size: Int, alignment: Int) {
    var size = 0
    var align = 0
    encoding.withCString { ptr in
      _ = NSGetSizeAndAlignment(ptr, &size, &align)
    }
    return (size, align)
  }

  /// Encodings whose true in-memory layout the FLEX size formula reproduces
  /// exactly — i.e. where the runtime and parser must agree byte-for-byte.
  /// (FLEX's aligned size is `sum + sum % align`, which coincides with the true
  /// padded size for these but not for every struct; the divergent cases are
  /// pinned separately below.)
  private static let oracleAgreementEncodings: [String] = [
    // Signed integers. NOTE: bare `l` is intentionally excluded — see
    // `bare long encodings keep FLEX's native long width` below.
    "c", "i", "s", "q",
    // Unsigned integers. NOTE: bare `L` excluded for the same reason.
    "C", "I", "S", "Q",
    // Floating point
    "f", "d", "D",
    // Bool, char string
    "B", "*",
    // Object-shaped pointers
    "@", "#", ":",
    // Quoted-class object
    "@\"NSString\"",
    // Raw pointers (always one word)
    "^i", "^d", "^v", "^^i", "^{CGRect={CGPoint=dd}{CGSize=dd}}", "^@",
    // Common structs
    "{CGPoint=dd}", "{CGSize=dd}", "{CGRect={CGPoint=dd}{CGSize=dd}}",
    "{_NSRange=QQ}", "{Anon=@i}",
    // Arrays
    "[4i]", "[8c]", "[3d]", "[2{CGPoint=dd}]", "[4^i]",
    // const-qualified
    "ri", "r^i",
  ]

  @Test(.scenario("scenario.runtime.type-encoding.scalar-sizes"))
  func `every supported encoding sizes to exactly what NSGetSizeAndAlignment reports`() throws {
    for encoding in Self.oracleAgreementEncodings {
      let oracle = Self.runtimeSizeAndAlignment(encoding)
      let parsed = try #require(
        TypeEncodingParser.sizeAndAlignment(of: encoding),
        "expected \(encoding) to be supported")
      #expect(
        parsed.size == oracle.size,
        "size mismatch for \(encoding): parser \(parsed.size) vs oracle \(oracle.size)")
      #expect(
        parsed.alignment == oracle.alignment,
        "alignment mismatch for \(encoding): parser \(parsed.alignment) vs oracle \(oracle.alignment)"
      )
    }
  }

  @Test(.scenario("scenario.runtime.type-encoding.struct-sizes"))
  func `nested structs size to the runtime value`() throws {
    for encoding in ["{CGPoint=dd}", "{CGRect={CGPoint=dd}{CGSize=dd}}", "{box={CGRect=dddd}i}"] {
      let oracle = Self.runtimeSizeAndAlignment(encoding)
      let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: encoding))
      #expect(parsed.size == oracle.size, "size for \(encoding)")
      #expect(parsed.alignment == oracle.alignment, "alignment for \(encoding)")
    }
  }

  @Test(.scenario("scenario.runtime.type-encoding.array-sizes"))
  func `arrays size to element times count`() throws {
    for encoding in ["[4i]", "[2{CGPoint=dd}]", "[3d]"] {
      let oracle = Self.runtimeSizeAndAlignment(encoding)
      let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: encoding))
      #expect(parsed.size == oracle.size, "size for \(encoding)")
    }
  }

  @Test(.scenario("scenario.runtime.type-encoding.pointer-sizes"))
  func `every pointer-shaped encoding sizes to one word`() throws {
    let word = MemoryLayout<UnsafeRawPointer>.size
    for encoding in ["^i", "^{CGRect={CGPoint=dd}{CGSize=dd}}", "*", "@", "#", ":", "^?", "^@"] {
      let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: encoding))
      #expect(parsed.size == word, "size for \(encoding)")
      #expect(parsed.alignment == word, "alignment for \(encoding)")
    }
  }

  @Test
  func `void sizes to zero and is supported`() throws {
    let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: "v"))
    #expect(parsed.size == 0)
  }

  @Test
  func `bare long encodings keep FLEX's native long width`() throws {
    // FLEX sizes `l`/`L` with `sizeof(long)` (8 on a 64-bit host), which is
    // faithful to the port but diverges from `NSGetSizeAndAlignment`, where a
    // bare `l`/`L` means the runtime's 32-bit long (4). FLEX's own tests never
    // compared bare `l`/`L` to the oracle (they tested `@encode(long)`, which is
    // `q`), so this divergence is preserved deliberately rather than "fixed".
    let nativeLong = MemoryLayout<CLong>.size
    let parsedL = try #require(TypeEncodingParser.sizeAndAlignment(of: "l"))
    let parsedUL = try #require(TypeEncodingParser.sizeAndAlignment(of: "L"))
    #expect(parsedL.size == nativeLong)
    #expect(parsedUL.size == nativeLong)
  }

  @Test(.scenario("scenario.runtime.type-encoding.bitfield-unsupported"))
  func `a bare bitfield is unsupported`() {
    #expect(TypeEncodingParser.sizeAndAlignment(of: "b8") == nil)
    #expect(TypeEncodingParser.sizeAndAlignment(of: "b1") == nil)
  }

  @Test(.scenario("scenario.runtime.type-encoding.bitfield-unsupported"))
  func `a struct containing a bitfield is unsupported`() {
    #expect(TypeEncodingParser.sizeAndAlignment(of: "{HasBitfield=b1}") == nil)
  }

  @Test(.scenario("scenario.runtime.type-encoding.malformed-safe"))
  func `malformed and nameless encodings are nil, never a crash`() {
    // Empty, truncated, and structurally invalid encodings.
    #expect(TypeEncodingParser.sizeAndAlignment(of: "") == nil)
    #expect(TypeEncodingParser.sizeAndAlignment(of: "{") == nil)
    #expect(TypeEncodingParser.sizeAndAlignment(of: "[4") == nil)
    #expect(TypeEncodingParser.sizeAndAlignment(of: "[]") == nil)
    #expect(TypeEncodingParser.sizeAndAlignment(of: "{?}") == nil)
    #expect(TypeEncodingParser.sizeAndAlignment(of: "^") == nil)
    // A type the parser cannot size at all.
    #expect(TypeEncodingParser.sizeAndAlignment(of: "Z") == nil)
  }

  @Test
  func `a union is sized by the parser as its largest member`() throws {
    // Unions ARE sizeable (largest member), even though NSMethodSignature
    // rejects them. `(?=ic)` is max(int 4, char 1) = 4.
    let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: "(?=ic)"))
    #expect(parsed.size == MemoryLayout<CInt>.size)
  }

  // MARK: - methodSignatureSupported

  @Test(.scenario("scenario.runtime.type-encoding.union-rejected"))
  func `method signatures with unsupported forms are rejected`() {
    // Verbatim from FLEX's testUnsupportedMethodSignatures.
    let unsupported = [
      "v40@0:8{?=}16d32",
      "{?=[4]}16@0:8}",
      "i48@0:8^{__CVBuffer=}16I24(pj_timestamp={?=II}Q)28i36B40B44",
    ]
    for signature in unsupported {
      #expect(
        !TypeEncodingParser.methodSignatureSupported(signature),
        "expected \(signature) to be unsupported")
    }
  }

  @Test
  func `an empty encoding is not a supported method signature`() {
    #expect(!TypeEncodingParser.methodSignatureSupported(""))
  }

  @Test
  func `a plain scalar return method signature is supported`() {
    // `i16@0:8` — returns int, self + _cmd.
    #expect(TypeEncodingParser.methodSignatureSupported("i16@0:8"))
    #expect(TypeEncodingParser.methodSignatureSupported("v16@0:8"))
  }

  // MARK: - cleaned

  @Test(.scenario("scenario.runtime.type-encoding.cleaning"))
  func `unclean method signatures are rewritten to the expected cleaned form`() throws {
    // Verbatim from FLEX's testMethodSignatureCleaning.
    let uncleanToClean: [(unclean: String, clean: String)] = [
      (
        "^{Layer=^^?{Atomic={?=i}}{Data={Vec4<float>=ffff}b1{Vec2<double>=dd}{Rect=dddd}}"
          + "{Ref<CA::Render::Object>=^{Object}}{Ref<CA::Render::TypedArray<CA::Render::Layer> >="
          + "^{TypedArray<CA::Render::Layer>}}^{Layer}{Ref<CA::Render::Layer::Ext>=^{Ext}}"
          + "{Ref<CA::Render::TypedArray<CA::Render::Animation> >="
          + "^{TypedArray<CA::Render::Animation>}}{Ref<CA::Render::Handle>=^{Handle}}}36@0:"
          + "8^{Transaction=^{Shared}i^{HashTable<CA::Layer *, unsigned int *>}^{SpinLock}I"
          + "^{Level}^{List<void (^)()>}^{Command}^{Deleted}^{List<const void *>}^{Context}"
          + "^{HashTable<CA::Layer *, CA::Layer *>}^{__CFRunLoop}^{__CFRunLoopObserver}"
          + "^{LayoutList}^{List<CA::Layer *>}{Atomic={?=i}}b1b1b1b1b1}16I24^I28",
        "^{Layer=}36@0:8^{Transaction=}16I24^I28"
      ),
      (
        "{LSBinding=I^{LSBundleData=}I^{?}@@}16@0:8",
        "{LSBinding=I^{LSBundleData=}I^{?=}@@}16@0:8"
      ),
      (
        "@40@0:8@16r^{?=BQ^{?}}24^@32",
        "@40@0:8@16r^{?=BQ^{?=}}24^@32"
      ),
      (
        "@36@0:8@16^{mig_subsystem=^?iiIQ[1{routine_descriptor=^?^?II^{?}I}]}24B32",
        "@36@0:8@16^{mig_subsystem=^?iiIQ[1{routine_descriptor=^?^?II^{?=}I}]}24B32"
      ),
      (
        "@28@0:8r^{basic_string<char, std::__1::char_traits<char>, "
          + "std::__1::allocator<char> >={__compressed_pair<std::__1::"
          + "basic_string<char, std::__1::char_traits<char>, "
          + "std::__1::allocator<char> >::__rep, std::__1::allocator<char> "
          + ">={__rep=(?={__long=QQ*}{__short=(?=Cc)[23c]}{__raw=[3Q]})}}}16B24",
        "@28@0:8r^{?=}16B24"
      ),
      (
        "^{nui_size_cache=^{pair<CGSize, CGSize>}^{pair<CGSize, CGSize>}"
          + "{__compressed_pair<std::__1::pair<CGSize, CGSize> *, "
          + "std::__1::allocator<std::__1::pair<CGSize, CGSize> > >="
          + "^{pair<CGSize, CGSize>}}}16@0:8",
        "^{nui_size_cache=}16@0:8"
      ),
      (
        "^?32@0:8r^{_CAPropertyInfo=I[2:]b16b16*^{__CFString}}16"
          + "r^{_CAPropertyInfo=I[2:]b16b16*^{__CFString}}24",
        "^?32@0:8r^{_CAPropertyInfo=}16r^{_CAPropertyInfo=}24"
      ),
      // NSMethodSignature doesn't support unions.
      (
        "^{?=(pj_timestamp={?=II}Q)Iii}20@0:8i16",
        "^{?=}20@0:8i16"
      ),
      (
        "^{KeyValueArray=^^?{Atomic={?=i}}I[1^{Object}]}16@0:8",
        "^{KeyValueArray=^^?{Atomic={?=i}}I[1^{Object=}]}16@0:8"
      ),
    ]

    for pair in uncleanToClean {
      #expect(
        TypeEncodingParser.methodSignatureSupported(pair.unclean),
        "expected \(pair.unclean) to be supported after cleaning")
      let cleaned = try #require(
        TypeEncodingParser.cleaned(pair.unclean),
        "expected a cleaned form for \(pair.unclean)")
      #expect(
        cleaned == pair.clean, "cleaned mismatch:\n  got      \(cleaned)\n  expected \(pair.clean)")
    }
  }

  @Test(.scenario("scenario.runtime.type-encoding.already-clean"))
  func `an already-supported method signature cleans to itself`() throws {
    for clean in ["i16@0:8", "v16@0:8", "@24@0:8@16", "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8"] {
      #expect(TypeEncodingParser.methodSignatureSupported(clean))
      let cleaned = try #require(TypeEncodingParser.cleaned(clean))
      #expect(cleaned == clean, "expected \(clean) to clean to itself, got \(cleaned)")
    }
  }

  // MARK: - edge cases (coverage gaps the adversarial verifier flagged)

  @Test
  func `an anonymous empty struct sizes to zero`() throws {
    // The *valid* empty form `{?=}` (distinct from the malformed `{?}`): zero-sized.
    let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: "{?=}"))
    #expect(parsed.size == 0)
  }

  @Test
  func `an opaque struct pointer and a block size to one word`() throws {
    let word = MemoryLayout<UnsafeRawPointer>.size
    // `^{Foo=}` opaque struct pointer; `@?` block; `r^v` const void* — all one pointer.
    for encoding in ["^{Foo=}", "@?", "r^v"] {
      let parsed = try #require(
        TypeEncodingParser.sizeAndAlignment(of: encoding), "expected \(encoding) supported")
      #expect(parsed.size == word, "size for \(encoding)")
      #expect(parsed.alignment == word, "alignment for \(encoding)")
    }
  }

  @Test
  func `a multidimensional and struct-element array sizes to the runtime value`() throws {
    // The oracle handles these valid arrays; pin alignment, which earlier array
    // tests omitted, and array-of-arrays which was uncovered.
    for encoding in ["[2{CGPoint=dd}]", "[2[3i]]", "[4^i]"] {
      let oracle = Self.runtimeSizeAndAlignment(encoding)
      let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: encoding))
      #expect(parsed.size == oracle.size, "size for \(encoding)")
      #expect(parsed.alignment == oracle.alignment, "alignment for \(encoding)")
    }
  }

  @Test(.scenario("scenario.runtime.type-encoding.malformed-safe"))
  func `a truncated tail ending in a qualifier or pointer is nil, never a crash`() {
    // These are exactly where FLEX-ObjC aborts (unguarded characterAtIndex:);
    // the Swift port must stay safe. Regression guard.
    for encoding in ["r", "^", "^^", "r^", "rr", "^r"] {
      #expect(
        TypeEncodingParser.sizeAndAlignment(of: encoding) == nil,
        "expected \(encoding) to be unsupported (not a crash)")
    }
  }

  @Test
  func `an all-void aggregate sizes to zero without a divide-by-zero`() throws {
    // Pins the `align != 0` guard against the `size % align` = `0 % 0` UB FLEX has.
    for encoding in ["{V=v}", "(u=v)"] {
      let parsed = try #require(
        TypeEncodingParser.sizeAndAlignment(of: encoding), "expected \(encoding) sizeable")
      #expect(parsed.size == 0, "size for \(encoding)")
    }
  }

  @Test
  func `a negative array count preserves FLEX's quirk`() throws {
    // FLEX computes `[-3i]` as count * elementSize = -3 * 4 = -12, align 4 — a
    // faithful quirk (not oracle-checkable; NSGetSizeAndAlignment rejects it).
    let parsed = try #require(TypeEncodingParser.sizeAndAlignment(of: "[-3i]"))
    #expect(parsed.size == -12)
    #expect(parsed.alignment == 4)
  }

  @Test(.scenario("scenario.runtime.type-encoding.cleaning"))
  func `a pointer to a union cleans the union away`() throws {
    // `^(?=ic)16@0:8` — a pointer to a union; the union is stripped to `^?`.
    #expect(TypeEncodingParser.methodSignatureSupported("^(?=ic)16@0:8"))
    let cleaned = try #require(TypeEncodingParser.cleaned("^(?=ic)16@0:8"))
    #expect(cleaned == "^?16@0:8", "got \(cleaned)")
  }

  @Test(.scenario("scenario.runtime.type-encoding.already-clean"))
  func `a block in a method signature survives cleaning`() throws {
    // `@?` blocks are supported and clean to themselves.
    #expect(TypeEncodingParser.methodSignatureSupported("@?16@0:8"))
    let cleaned = try #require(TypeEncodingParser.cleaned("@?16@0:8"))
    #expect(cleaned == "@?16@0:8", "got \(cleaned)")
  }
}
