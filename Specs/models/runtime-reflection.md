---
id: domain.runtime.reflection
kind: domain
depends-on: [domain.runtime.type-encoding]
---

# Domain: Objective-C runtime reflection (metadata)

The half of `RuntimeKit` that reads **runtime metadata** off a live Objective-C
class with `<objc/runtime.h>` — the ivars, methods, properties, and protocols a
class declares — and projects each into a plain, `Sendable` Swift value type. It
is the metadata port of FLEX's `Objc/Reflection/` cluster (`FLEXIvar`,
`FLEXMethod`, `FLEXProperty`, `FLEXProtocol`), reduced to its **reflection**
surface: *what members does this class have, and what do they look like?*

This layer is deliberately **metadata-only**. It does not read or write ivar
values, does not invoke methods, and does not box/unbox primitives — the
`NSInvocation` / `va_list` / `object_getIvar` machinery of FLEX is **out of
headless scope** and is intentionally dropped (see "What is dropped" below). The
inputs are an `AnyClass` (or a metaclass, or a `Protocol`); the outputs are
arrays of immutable value types. No injection, no target process — reflecting a
class that is already loaded in *this* process is deterministic and testable on
any Mac with no SIP changes.

Unlike `domain.runtime.type-encoding`, this layer **does** import the runtime
(`ObjectiveC`). The malloc'd-C-array runtime calls (`class_copyIvarList`,
`class_copyMethodList`, `class_copyPropertyList`, `protocol_copy*`) are the only
I/O; each call is wrapped in the standard `count`/`free`/`UnsafeBufferPointer`
idiom and immediately mapped into value types, so the runtime pointers never
escape the constructor.

## The value-type shapes

All four are immutable `public struct … : Sendable` value types. The field names
are a shared contract: `RuntimeMirror` (a sibling spec) aggregates these exact
shapes, so the names below are load-bearing and must not drift.

### `RuntimeIvar` — one instance variable

Port of the metadata half of `FLEXIvar`.

| Field          | Type     | Source                                                       |
| -------------- | -------- | ------------------------------------------------------------ |
| `name`         | `String` | `ivar_getName`                                               |
| `offset`       | `Int`    | `ivar_getOffset`                                             |
| `typeEncoding` | `String` | `ivar_getTypeEncoding` (`""` when the runtime returns null)  |
| `size`         | `Int`    | `TypeEncodingParser.sizeAndAlignment(of:)?.size`, else `0`   |

- **`static func ivars(of cls: AnyClass) -> [RuntimeIvar]`** — every ivar the
  class *itself* declares (not inherited), in runtime order, via
  `class_copyIvarList`. An ivar whose name the runtime cannot read is skipped.
- The **size** comes from the pure `TypeEncodingParser`, not from
  `NSGetSizeAndAlignment` — faithful to FLEX's `FLEXGetSizeAndAlignment`, which
  is the same parser. A type the parser cannot size yields `0` (FLEX's "0 if
  unknown" contract), never a crash.
- A null / empty type encoding (`ivar_getTypeEncoding` returned null) yields
  `typeEncoding == ""` and `size == 0`.

### `RuntimeMethod` — one method

Port of the metadata half of `FLEXMethod`.

| Field          | Type     | Source                                                       |
| -------------- | -------- | ------------------------------------------------------------ |
| `selectorName` | `String` | `sel_getName(method_getName(...))`                           |
| `typeEncoding` | `String` | `method_getTypeEncoding` (`""` when the runtime returns null)|
| `argumentCount`| `Int`    | `method_getNumberOfArguments`                                |

- **`static func methods(of cls: AnyClass) -> [RuntimeMethod]`** — every
  *instance* method the class itself declares, via `class_copyMethodList(cls, …)`.
- **`static func classMethods(of cls: AnyClass) -> [RuntimeMethod]`** — every
  *class* method, via `class_copyMethodList(object_getClass(cls), …)` over the
  metaclass. Returns `[]` when the metaclass is unavailable.
- `argumentCount` is the runtime's count, which always includes the two implicit
  arguments `self` (`@`) and `_cmd` (`:`) — so a zero-argument selector reports
  `2`. This is `method_getNumberOfArguments`, carried verbatim.
- The `typeEncoding` here is the **full method signature** the runtime stores
  (return type followed by the argument frame with offsets, e.g. `v16@0:8`). It
  is *not* run through `TypeEncodingParser.cleaned(_:)` — cleaning is only needed
  when the encoding is handed to `NSMethodSignature`, which the metadata layer
  never does.

### `RuntimeProperty` — one declared property

Port of the metadata half of `FLEXProperty`.

| Field          | Type                | Source                       |
| -------------- | ------------------- | ---------------------------- |
| `name`         | `String`            | `property_getName`           |
| `typeEncoding` | `String`            | the `T…` attribute (`""` if absent) |
| `attributes`   | `PropertyAttributes`| parsed `property_getAttributes` |

- **`static func properties(of cls: AnyClass) -> [RuntimeProperty]`** — every
  *instance* property the class itself declares, in runtime order, via
  `class_copyPropertyList`.
- **`static func classProperties(of cls: AnyClass) -> [RuntimeProperty]`** —
  every *class* property, via `class_copyPropertyList(objc_getMetaClass(name), …)`
  over the metaclass. Returns `[]` when the metaclass is unavailable.
- `typeEncoding` is a convenience mirror of `attributes.typeEncoding ?? ""`, so a
  consumer wanting only the type need not reach into the attributes. (FLEX
  FB7499230 caveat: the `T…` encoding the runtime emits is not always correct.)

#### `PropertyAttributes` — the parsed attribute string

Port of `FLEXPropertyAttributes` + `NSString+ObjcRuntime`'s `propertyAttributes`,
minus the mutable subclass and `class_replaceProperty` list-rebuilding (out of
headless scope). `property_getAttributes` returns a comma-separated string
(`T@"NSString",C,N,V_title`); each component is keyed by its **first character**:

| Char | Field                | Kind  | Meaning                                   |
| ---- | -------------------- | ----- | ----------------------------------------- |
| `T`  | `typeEncoding`       | value | the property's type encoding              |
| `V`  | `backingIvar`        | value | name of the backing ivar                  |
| `G`  | `customGetter`       | value | custom getter selector name               |
| `S`  | `customSetter`       | value | custom setter selector name               |
| `t`  | `oldTypeEncoding`    | value | old-style type encoding                   |
| `R`  | `isReadOnly`         | flag  | `readonly`                                |
| `C`  | `isCopy`             | flag  | `copy`                                    |
| `&`  | `isRetained`         | flag  | `retain` / `strong`                       |
| `N`  | `isNonatomic`        | flag  | `nonatomic`                               |
| `D`  | `isDynamic`          | flag  | `@dynamic`                                |
| `W`  | `isWeak`             | flag  | `weak`                                    |
| `P`  | `isGarbageCollected` | flag  | GC-eligible (legacy; unset on modern targets) |

`PropertyAttributes(parsing: String)` is **total**: flags default to `false` when
their char is absent, value fields to `nil`, unknown chars are ignored (FLEX's
`switch` has no `default`), and an empty string yields an all-default value. A
component that is a lone key char with no value (`V` with nothing after) yields an
empty-string value, matching FLEX's `stringByDeletingCharacterAtIndex:0`.

### `RuntimeProtocol` — one protocol

Port of the metadata half of `FLEXProtocol` (owned by a sibling agent;
field-shape contract pinned here).

| Field                | Type                   | Source                       |
| -------------------- | ---------------------- | ---------------------------- |
| `name`               | `String`               | `protocol_getName`           |
| `conformedProtocols` | `[String]`             | `protocol_copyProtocolList`  |
| (method descriptions)| `[ProtocolMethod]`     | `protocol_copyMethodDescriptionList` |

## Purity boundary

- The four shapes are `Sendable` value types with no runtime pointers retained —
  once constructed they can cross threads and outlive the class. The `Ivar` /
  `Method` / `objc_property_t` / `Protocol` handles never escape the `static`
  constructors.
- The constructors are the **only** I/O. Mapping a runtime handle into a value
  type is pure; sizing leans on `domain.runtime.type-encoding`, which is itself
  pure. So everything downstream of the `class_copy…` call is testable in
  isolation.

## What is dropped from FLEX (out of headless scope)

The metadata port deliberately omits the *value* and *invocation* halves of the
FLEX reflection classes:

- **`FLEXIvar`**: `getValue:`, `setValue:onObject:`, `getPotentiallyUnboxedValue:`
  — all ivar value get/set, tagged-pointer and non-pointer-isa handling, and
  primitive boxing. RuntimeKit reflects the ivar's *shape*, never its value.
- **`FLEXMethod`**: `sendMessage:`, `getReturnValue:forMessageSend:`, the
  `NSInvocation` + `va_list` dispatch, `implementation` get/set,
  `swapImplementations:`, `method_exchangeImplementations`, and the
  `NSMethodSignature`-derived `returnType` / `returnSize` / `signature`. None of
  the invocation machinery is ported.
- **`description` / `prettyName` / `debugName…` / `imagePath`** — human-readable
  rendering and `dladdr` image lookup are presentation concerns, not metadata,
  and are dropped. (`imagePath` may return as a separate concern if a consumer
  needs it; it is not part of the metadata shape.)
- The `+named:onClass:` / `+selector:class:` *lookup* convenience initializers
  are dropped in favor of the bulk `…(of:)` enumerators, which are what
  `RuntimeMirror` needs. A single-member lookup can be added when a consumer
  requires it.

## The safety denylist (`RuntimeSafety`)

A faithful port of FLEX's `FLEXRuntimeSafety`. Some classes and ivars are
**unsafe to introspect** — touching them (sending `+class`, reading an ivar,
building an `NSMethodSignature` over a member) crashes, hangs, or corrupts state.
FLEX hard-codes a small denylist and the reflection cluster consults it before
deeper introspection (`FLEXClassIsSafe`, `FLEXIvarIsSafe`). `RuntimeSafety`
carries the same entries.

In FLEX the denylist is materialized by an `__attribute__((constructor))` that
runs at load and builds two `CFSetRef`s. The Swift port **drops the constructor**:
the denylist becomes a lazy `static let Set<String>`, computed on first use — no
load-time work, no global mutable runtime state.

- **`classIsSafe(_ cls: AnyClass) -> Bool`** — false if the class is one of the
  known-unsafe classes (matched by `NSStringFromClass` name). FLEX additionally
  rejects a class whose superclass is `nil` (a root class) **unless** it is
  exactly `NSObject` or `NSProxy`; the port preserves that root-class rule. A
  `nil` class is unsafe (the Swift signature takes a non-optional `AnyClass`, so
  the `nil` arm survives as the documented contract, exercised via the name set).
- **`ivarIsSafe(_ name: String, on cls: AnyClass) -> Bool`** — false if
  `(class, ivar-name)` is a known-unsafe pair. FLEX keys this on the `Ivar`
  pointer identity of `NSURL._urlString` / `NSURL._baseURL`; under non-injected
  reflection the `(class-chain, name)` pair selects exactly the same ivars, so
  the port keys on the name, walking up the superclass chain (an `NSURL` subclass
  inherits the unsafe ivars).

### Known-unsafe classes (carried verbatim from FLEX, 19 entries)

`__ARCLite__`, `__NSCFCalendar`, `__NSCFTimer`, `NSCFTimer`,
`__NSGenericDeallocHandler`, `NSAutoreleasePool`, `NSPlaceholderNumber`,
`NSPlaceholderString`, `NSPlaceholderValue`, `Object`, `VMUArchitecture`,
`JSExport`, `__NSAtom`, `_NSZombie_`, `_CNZombie_`, `__NSMessage`,
`__NSMessageBuilder`, `FigIrisAutoTrimmerMotionSampleExport`, `_UIPointVector`.

(`_UIPointVector` is on the list because its `setVectors:` has an invalid type
encoding that crashes `NSMethodSignature` — a hazard `domain.runtime.type-encoding`
now defuses, but the denylist entry is preserved for fidelity.)

### Known-unsafe ivars (carried verbatim from FLEX)

`NSURL._urlString`, `NSURL._baseURL`.

### Safety invariants

- **Unsafe is rejected before introspection.** `classIsSafe` / `ivarIsSafe`
  return `false` for every denylist entry without performing any deeper read.
- **Ordinary classes pass.** A non-denylisted, non-root class — and `NSObject` /
  `NSProxy` themselves — are safe.
- **No load-time work.** The denylist is a lazy `static let`; there is no
  `__attribute__((constructor))` and no global mutable runtime state.

## Test oracle

No injection. The oracle is reflection of a **known class in the test process
itself** — a small `@objc` fixture (`@objc(RKFixture) class RKFixture: NSObject`)
with declared `@objc` ivars, instance methods, and class methods of known
shape, plus well-known Foundation/ObjC classes. The reflection must find exactly
the declared members with the expected names, offsets-in-order, encodings, and
argument counts. For `RuntimeSafety` the oracle is the denylist itself: every
known-unsafe class/ivar must be rejected and an ordinary class/ivar must pass.
Deterministic; runs on any Mac.

## Acceptance

- `[scenario.runtime.safety.class-rejected]` Every known-unsafe class name is
  rejected by `classIsSafe`.
- `[scenario.runtime.safety.class-allowed]` An ordinary class — and `NSObject` /
  `NSProxy` — pass `classIsSafe`.
- `[scenario.runtime.safety.root-class]` A root class (no superclass) other than
  `NSObject` / `NSProxy` is rejected by `classIsSafe`.
- `[scenario.runtime.safety.ivar-rejected]` `NSURL._urlString` and
  `NSURL._baseURL` are rejected by `ivarIsSafe`.
- `[scenario.runtime.safety.ivar-allowed]` An ordinary ivar passes `ivarIsSafe`.
- `[scenario.runtime.reflection.declared-property]` Reflecting a fixture class
  finds a declared property by name with the expected type encoding.
- `[scenario.runtime.reflection.readonly-attribute]` A `readonly` property parses
  to `isReadOnly == true`; a `readwrite` one to `false`.
- `[scenario.runtime.reflection.storage-attributes]` `copy` / `strong` / `weak`
  storage attributes parse to `isCopy` / `isRetained` / `isWeak`, and
  `nonatomic` to `isNonatomic`.
- `[scenario.runtime.reflection.backing-ivar]` A property's `V` component parses
  to `backingIvar`.
- `[scenario.runtime.reflection.custom-accessors]` `getter=`/`setter=` parse to
  `customGetter` / `customSetter`.
- `[scenario.runtime.reflection.class-property]` `classProperties(of:)` finds a
  declared class property the instance reflector does not.
- `[scenario.runtime.reflection.declared-only]` A property reflector returns only
  the class's own properties, never inherited ones.
- `[scenario.runtime.reflection.empty-attributes]` Parsing degenerate attribute
  strings (`""`, lone flags, unknown chars) does not crash.
