---
id: domain.runtime.type-encoding
kind: domain
---

# Domain: Objective-C type-encoding parsing

The pure-Swift core of `RuntimeKit` that reads Objective-C **type encodings** — the
`@encode(...)` strings the runtime emits for ivars, properties, method arguments,
and return types (`i`, `^{CGRect=…}`, `[4f]`, `(?=II)`) — and answers two
questions about them: *how big is this type?* and *can this method signature be
handed to `NSMethodSignature` safely?* It is a faithful port of FLEX's
`FLEXTypeEncodingParser` / `FLEXRuntimeConstants`. See `ARCHITECTURE.md` →
"Shared foundations".

`RuntimeKit`'s type-encoding layer is **pure**: parsing an encoding is string
recursion over structs, unions, arrays, and pointers. It imports **Foundation
only** — no `objc/runtime.h`, no live runtime, no `NSGetSizeAndAlignment`. It
therefore runs and is unit-testable on any Mac with no SIP changes and no
injection. (Its sizing must *agree* with `NSGetSizeAndAlignment`; it does not
*call* it.)

## The `TypeEncoding` model

A `Character`-backed `enum` mapping every encoding byte, faithful to FLEX's
`FLEXTypeEncoding`:

| Char | Case | Char | Case | Char | Case |
| --- | --- | --- | --- | --- | --- |
| `\0` | `null` | `q` | `longLong` | `*` | `cString` |
| `?` | `unknown` | `C` | `unsignedChar` | `@` | `objcObject` |
| `c` | `char` | `I` | `unsignedInt` | `#` | `objcClass` |
| `i` | `int` | `S` | `unsignedShort` | `:` | `selector` |
| `s` | `short` | `L` | `unsignedLong` | `[` `]` | `arrayBegin` `arrayEnd` |
| `l` | `long` | `Q` | `unsignedLongLong` | `{` `}` | `structBegin` `structEnd` |
| `f` | `float` | `B` | `cBool` | `(` `)` | `unionBegin` `unionEnd` |
| `d` | `double` | `v` | `void` | `"` | `quote` |
| `D` | `longDouble` | `^` | `pointer` | `b` | `bitField` |
| | | `r` | `const` | | |

`TypeEncoding(rawValue:)` recognizes a byte from an encoding string directly. The
sizing constant `TypeEncodingSizes.pointer` names the pointer width (8 on every
supported 64-bit target) so the `id`/`Class`/`SEL`/`^`/`*`/`?` sizes read as a
deliberate contract rather than a literal.

## The parser contract (`TypeEncodingParser`)

- **`sizeAndAlignment(of:) -> (size: Int, alignment: Int)?`** — the in-memory
  `(size, alignment)` of one type encoding, or `nil` if the type is unsupported.
  Recurses through structs (sum of members), unions (largest member), arrays
  (element × count), and pointers. Defaults to the *aligned* size. Mirrors FLEX's
  `+sizeForTypeEncoding:alignment:`.
- **`size(ofTypeEncoding:alignment:unaligned:) -> Int`** — the size in bytes (or
  `-1`), writing the alignment to the `inout`. `unaligned: true` returns the raw
  member-sum size; the aligned size adds `size % align` (FLEX's exact arithmetic,
  not a round-up-to-multiple — preserved because the oracle was matched to it).
- **`methodSignatureSupported(_:) -> Bool`** — whether a **full method type
  encoding** (return type + argument frame) can be passed to `NSMethodSignature`
  without it throwing `objc_exception_throw`. False if any type in the frame is
  unsupported, contains a union, or is zero-size and not `void`.
- **`cleaned(_:) -> String?`** — the "safe" rewrite of a method type encoding,
  with the forms `NSMethodSignature` rejects replaced: unions, unsupported
  pointer-to-struct, and nameless C++ structs become `{Name=}` / `^?` / `{?=}`.
  `nil` if the encoding is unsupported even after cleaning.

### What is unsupported, and why

- **Bitfields (`b8`) outside a struct** — the encoding carries no alignment, so
  the type cannot be sized; rejected.
- **Bitfields as struct members** — a struct containing a `b…` member is
  rejected entirely (FLEX: it bails the whole struct).
- **Unions (`(…)`)** — sizeable by `NSGetSizeAndAlignment` but rejected by
  `NSMethodSignature`, so a top-level/argument union fails `methodSignatureSupported`,
  and a union *inside a pointer* is cleaned out (`^(…)` → `^?`).
- **Unsupported pointer-to-struct** — a pointer to a struct with no member info
  (`^{Foo}`) or a malformed/unsupported pointee is rewritten to a named-but-empty
  struct (`^{Foo=}`) or `^?`.

## Invariants

1. **NSGetSizeAndAlignment agreement.** For every encoding the runtime can size,
   `sizeAndAlignment(of:)` returns the same `(size, alignment)` the runtime would
   compute — verified at test time against `NSGetSizeAndAlignment` itself as the
   oracle, never hard-coded.
2. **Unsupported is `nil`, never a crash.** Bitfields, malformed arrays, and
   nameless `{?}` return `nil` (or `false`) rather than throwing or trapping. The
   parser never indexes out of bounds on a truncated or malformed encoding.
3. **Cleaning is idempotent on already-clean input.** A method encoding with no
   union / unsupported pointer is returned unchanged by `cleaned(_:)`.
4. **Cleaning preserves what it can.** A named struct behind an unsupported
   pointer keeps its name (`^{Foo=…}` → `^{Foo=}`); only nameless or C++ forms
   collapse to `?` / `{?=}`.
5. **Pure.** Foundation only — no `objc/runtime.h`, no runtime calls, no
   `NSGetSizeAndAlignment` in the implementation. Runs on any Mac.

## Acceptance

- `[scenario.runtime.type-encoding.scalar-sizes]` Every scalar encoding sizes to
  exactly what `NSGetSizeAndAlignment` reports.
- `[scenario.runtime.type-encoding.struct-sizes]` Common structs (`{CGPoint=dd}`,
  `{CGRect={CGPoint=dd}{CGSize=dd}}`) size to the runtime's value.
- `[scenario.runtime.type-encoding.array-sizes]` Arrays (`[4i]`, `[2{CGPoint=dd}]`)
  size to element × count, matching the runtime.
- `[scenario.runtime.type-encoding.pointer-sizes]` Pointer encodings (`^i`,
  `^{CGRect=…}`, `*`, `@`, `#`, `:`) size to one pointer.
- `[scenario.runtime.type-encoding.bitfield-unsupported]` A bare bitfield is
  unsupported (`nil`); `NSGetSizeAndAlignment` would throw on the equivalent.
- `[scenario.runtime.type-encoding.union-rejected]` A method signature carrying a
  union is rejected by `methodSignatureSupported`.
- `[scenario.runtime.type-encoding.cleaning]` Unclean method encodings are
  rewritten to the exact cleaned form (unions stripped, unsupported
  pointer-to-struct named-or-`?`d).
- `[scenario.runtime.type-encoding.already-clean]` An already-supported method
  encoding cleans to itself.
- `[scenario.runtime.type-encoding.malformed-safe]` Malformed encodings return
  `nil`/`false` rather than crashing.
