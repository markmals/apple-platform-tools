---
id: domain.runtime.walker
kind: domain
depends-on: [domain.runtime.reflection]
---

# Domain: the headless AppKit walker (snapshots)

The half of `RuntimeKit` that reads a **live AppKit object** on the main thread
and projects it into a plain, `Sendable`, `Codable` snapshot value type. It is
the Swift port of FLEX's headless macOS AppKit walker — the
`Classes/ViewHierarchy/AppKit/FLEX*` cluster (`FLEXAppKitWalker`,
`FLEXAppKitViewSnapshot` / `FLEXAppKitWindowSnapshot`, `FLEXAppKitFont`,
`FLEXAppKitColor`, `FLEXAppKitLayer`, `FLEXConstraintNode`, `FLEXAppKitJSON`).

Where `domain.runtime.reflection` reads runtime *metadata* off a class with no
live object, this layer reads the *state* of a live view, window, font, color,
or layer. Two rules separate the layers and make the snapshots safe to serialize
off the main thread:

- **The reader is `@MainActor`.** AppKit reads must happen on the main thread.
  Every `snapshot(of:…)` entry point is main-actor-isolated.
- **The snapshot is plain data.** A snapshot struct holds only `Sendable`,
  `Codable` scalars — `String`, `Double`, `Bool`, nested snapshots — and
  **never** an `NSView`, `NSColor`, `NSFont`, or `CALayer` reference. The live
  object does not escape the constructor, so the value crosses actor and IPC
  boundaries freely and a stored AppKit reference would not compile.

Snapshots store **raw** values: a `CGFloat` becomes a `Double` with no rounding.
Deterministic JSON rounding (`stableRounded`) is a later concern of the
`AgentCLI` output encoder, not of these structs — they carry the truth as read.

The **real class name** of any reflected object is the runtime ISA, not the
static Swift type: `NSStringFromClass(object_getClass(x)!)`, never
`String(describing: type(of: x))` — the latter erases the private/KVO subclass
the walker exists to surface.

## `ColorSnapshot` — one resolved NSColor

Port of `FLEXAppKitColor`. A resolved color fact: the unambiguous sRGB hex, plus
— for live `NSColor` inputs — the catalog/dynamic name where one exists and the
appearance context it was resolved under.

```swift
public struct ColorSnapshot: Sendable, Codable {
  public let hex: String          // "#RRGGBBAA", sRGB, uppercase
  public let catalogName: String? // e.g. "labelColor", catalog colors only
  public let appearanceName: String? // e.g. "NSAppearanceNameDarkAqua"
}

@MainActor
public static func snapshot(of color: NSColor, appearance: NSAppearance?) -> ColorSnapshot
```

### The guard order is load-bearing

NSColor's component accessors throw Objective-C exceptions when called on the
wrong color type — `colorNameComponent` throws on a non-catalog color, and the
`redComponent` / `greenComponent` / … family throws on a color that is not
already in an RGB color space. **Swift cannot catch an Objective-C exception**,
so a throw here is an uncatchable crash, not a recoverable error. Every read is
therefore *guarded by type first*, never attempted speculatively:

1. **Catalog name first, only when the color is catalog.** Read
   `colorNameComponent` *only* when `color.type == .catalog`. For any other
   type, `catalogName` is `nil` and the accessor is never touched.
2. **Record the appearance name.** `appearanceName` is the passed appearance's
   `name` (its raw value), or `nil` when no appearance was supplied.
3. **Convert before reading components.** Resolve to sRGB with
   `usingColorSpace(.sRGB)` — *under* the appearance for a live catalog/dynamic
   color (otherwise it resolves under the wrong appearance or returns nil). Read
   `redComponent` / … **only** on the converted sRGB color.
4. **Hex from the converted color.** Each component is scaled `* 255` and rounded
   (`lround`) to an integer; the hex is `#%02X%02X%02X%02X` over R, G, B, A. If
   the color cannot be converted to sRGB (e.g. a pattern color), the hex is the
   empty string — never a misleading value read off an unguarded accessor.

A catalog/dynamic color is resolved through the appearance with
`performAsCurrentDrawingAppearance` (macOS 11+) wrapped around the conversion, so
the sRGB components reflect the requested appearance, not the process default.

## `FontSnapshot` — decomposed NSFont facts

Port of `FLEXAppKitFont`. Decomposes one `NSFont` into the facts a layout
reviewer needs, emitting the **raw CoreText weight trait** *and* the **nearest
named weight** — never a lossy `NSFontManager` (1–14) conversion.

```swift
public struct FontSnapshot: Sendable, Codable {
  public let family: String          // NSFont.familyName ?? fontName
  public let size: Double            // NSFont.pointSize (raw)
  public let weightTrait: Double     // raw NSFontWeightTrait from the symbolic-traits dict, [-1, 1]; 0 when omitted
  public let weightName: String      // nearest named bucket (ultraLight … black) to weightTrait
  public let postScriptName: String? // NSFont.fontName, the PostScript name
  public let traits: [String]        // symbolic traits present (bold, italic, …)
}

@MainActor
public static func snapshot(of font: NSFont) -> FontSnapshot
```

- **`family`** is `font.familyName`, falling back to `font.fontName` when AppKit
  reports no family. Never empty for a real font.
- **`size`** is `font.pointSize`, raw — not rounded.
- **`weightTrait`** is the raw CoreText `NSFontWeightTrait` read out of the
  descriptor's `NSFontTraitsAttribute` dictionary, in `[-1.0, 1.0]`, full
  precision. `0.0` when the descriptor omits it. This is *not* the symbolic
  `bold` flag and *not* the 1–14 `NSFontManager` weight — it is the continuous
  CoreText axis.
- **`weightName`** is the nearest named bucket to `weightTrait`, chosen by
  minimizing `abs(weightTrait − constant)` over AppKit's own `NSFont.Weight`
  constants so the thresholds track the platform rather than hardcoded folklore
  numbers:

  | Bucket | Constant |
  | --- | --- |
  | `ultraLight` | `NSFont.Weight.ultraLight` |
  | `thin` | `NSFont.Weight.thin` |
  | `light` | `NSFont.Weight.light` |
  | `regular` | `NSFont.Weight.regular` |
  | `medium` | `NSFont.Weight.medium` |
  | `semibold` | `NSFont.Weight.semibold` |
  | `bold` | `NSFont.Weight.bold` |
  | `heavy` | `NSFont.Weight.heavy` |
  | `black` | `NSFont.Weight.black` |

  Ties and the empty case resolve to `regular` (the seed default), matching
  FLEX's loop seed.
- **`postScriptName`** is `font.fontName` (e.g. `.SFNS-Bold`), the PostScript
  name; `nil` only when AppKit reports none.
- **`traits`** lists the symbolic traits present on
  `font.fontDescriptor.symbolicTraits`, in this fixed order: `bold`, `italic`,
  `expanded`, `condensed`, `monoSpace`, `vertical`, `uiOptimized`. Each appears
  only when its bit is set.

### Deviation from FLEX's carrier duck-typing

FLEX's `+fontForObject:` duck-types: it `performSelector:@selector(font)` on an
arbitrary `id`, then on its `-cell`, and narrows the result with
`isKindOfClass:[NSFont class]`. The Swift port narrows cleanly instead: the
reader takes an `NSFont` directly. Pulling a font *off a carrier* (a control or
its cell) is the walker's job, performed with a typed AppKit read or
`value(forKey: "font")`, not a raw `performSelector:` — so the snapshot reader's
input is already a real `NSFont`.

## `ConstraintNode` — one view's Auto Layout snapshot

Port of `FLEXConstraintNode.{h,m}` (with its `FLEXConstraint` / `FLEXConstraintItem`
helpers). Auto Layout extraction for **one** `NSView`: every `NSLayoutConstraint`
touching it, plus the view's intrinsic-sizing facts. `NSLayoutConstraint` is the
same class on macOS and iOS, so the shape is cross-platform; the reader is AppKit.

```swift
public struct ConstraintNode: Sendable, Codable {
  public let translatesAutoresizingMaskIntoConstraints: Bool
  public let intrinsicContentSize: IntrinsicSize
  public let contentHuggingHorizontal: Double
  public let contentHuggingVertical: Double
  public let compressionResistanceHorizontal: Double
  public let compressionResistanceVertical: Double
  public let constraints: [ConstraintDescription]
}

@MainActor
public static func snapshot(of view: NSView) -> ConstraintNode
```

| Field                                       | Source                                                              |
| ------------------------------------------- | ------------------------------------------------------------------- |
| `translatesAutoresizingMaskIntoConstraints` | `view.translatesAutoresizingMaskIntoConstraints`                    |
| `intrinsicContentSize`                      | `view.intrinsicContentSize` (raw; a no-metric axis is `-1`)         |
| `contentHuggingHorizontal`                  | `contentHuggingPriority(for: .horizontal)` raw value                |
| `contentHuggingVertical`                    | `contentHuggingPriority(for: .vertical)` raw value                  |
| `compressionResistanceHorizontal`           | `contentCompressionResistancePriority(for: .horizontal)` raw value  |
| `compressionResistanceVertical`             | `contentCompressionResistancePriority(for: .vertical)` raw value    |
| `constraints`                               | the touching constraints, both directions, deduplicated             |

### `IntrinsicSize` — a raw `{width, height}` value type

`public struct IntrinsicSize: Sendable, Codable { let width, height: Double }`.
Carries `intrinsicContentSize` verbatim. An axis with no intrinsic metric is
`NSView.noIntrinsicMetric` (`-1`), carried **as `-1`** — not rounded, not mapped
to `nil`. FLEX stores the raw `CGSize` with the sentinel intact; the
`-1` → "no intrinsic metric" interpretation is a presentation concern downstream.

### `ConstraintDescription` — one `NSLayoutConstraint`

Port of `FLEXConstraint`. Captures one constraint as
`first.attr (relation) second.attr * multiplier + constant @ priority`.

| Field        | Type             | Source                                                   |
| ------------ | ---------------- | -------------------------------------------------------- |
| `first`      | `ConstraintItem` | `firstItem` + `firstAttribute`                           |
| `relation`   | `String`         | `relation`, as a readable string (relation map)          |
| `second`     | `ConstraintItem` | `secondItem` + `secondAttribute`                         |
| `multiplier` | `Double`         | `multiplier`                                             |
| `constant`   | `Double`         | `constant` (raw)                                         |
| `priority`   | `Double`         | `priority` (the `NSLayoutConstraint.Priority` raw value) |
| `isActive`   | `Bool`           | `isActive`                                               |
| `identifier` | `String?`        | `identifier`                                             |

### `ConstraintItem` — one side of a constraint

Port of `FLEXConstraintItem`.

| Field       | Type      | Source                                                                           |
| ----------- | --------- | -------------------------------------------------------------------------------- |
| `className` | `String?` | `NSStringFromClass(object_getClass(item))`; `nil` for an absent (constant) item  |
| `attribute` | `String`  | the attribute, as a readable string (attribute map)                              |
| `kind`      | `String`  | `"view"` \| `"layoutGuide"` \| `"other"` \| `"none"`                              |
| `isTarget`  | `Bool`    | true when this item **is** the view the `ConstraintNode` describes               |

For an absent item (a constant constraint's `secondItem == nil`): `className == nil`,
`kind == "none"`, `isTarget == false`, and `attribute` still reflects
`secondAttribute` (which is `.notAnAttribute` → `"notAnAttribute"`). `kind` is
`"view"` when the item `is NSView`, `"layoutGuide"` when it `is NSLayoutGuide`,
`"other"` otherwise — `NSView` is checked first (faithful to FLEX).

### The relation string map (port of `FLEXRelationName`)

| `NSLayoutConstraint.Relation` | String               |
| ----------------------------- | -------------------- |
| `.lessThanOrEqual`            | `lessThanOrEqual`    |
| `.equal`                      | `equal`              |
| `.greaterThanOrEqual`         | `greaterThanOrEqual` |
| (unknown raw value `n`)       | `relation(n)`        |

### The attribute string map (port of `FLEXAttrName`)

| `NSLayoutConstraint.Attribute` | String           |
| ------------------------------ | ---------------- |
| `.left`                        | `left`           |
| `.right`                       | `right`          |
| `.top`                         | `top`            |
| `.bottom`                      | `bottom`         |
| `.leading`                     | `leading`        |
| `.trailing`                    | `trailing`       |
| `.width`                       | `width`          |
| `.height`                      | `height`         |
| `.centerX`                     | `centerX`        |
| `.centerY`                     | `centerY`        |
| `.lastBaseline`                | `lastBaseline`   |
| `.firstBaseline`               | `firstBaseline`  |
| `.notAnAttribute`              | `notAnAttribute` |
| (unknown raw value `n`)        | `attr(n)`        |

FLEX's `default` arms emit `relation(%ld)` / `attr(%ld)` over the raw integer; an
unrecognized raw value falls through to the parameterized form, preserving fidelity.

### Constraint collection (port of `+constraintsForView:`)

The constraints that **touch** the view — those where the view is the `firstItem`
or the `secondItem` — in both directions:

1. The view's own `constraints` that reference it. A view also holds constraints
   purely *between its descendants*; those don't touch it and are excluded.
2. Every ancestor's `constraints` that reference it. AppKit has no public reverse
   index, so the ancestor chain (`superview` up to the root) is walked and each
   ancestor's `constraints` filtered for ones touching the view.

Both passes apply the same **touch filter** (`firstItem === view ||
secondItem === view`) and the same **dedup**: a constraint is keyed by
`ObjectIdentifier` and added at most once. FLEX keys on a
`valueWithNonretainedObject:` box in an `NSMutableSet`; `ObjectIdentifier` is the
Swift equivalent — identity, no retain. Anything in `constraints` that is not an
`NSLayoutConstraint` is skipped (faithful to FLEX's `isKindOfClass:` guard).

### Purity boundary

The reader (`snapshot(of:)`) is the only I/O and is `@MainActor`; everything it
touches is read on main and immediately decomposed. The snapshot value types
(`ConstraintNode`, `ConstraintDescription`, `ConstraintItem`, `IntrinsicSize`)
retain no AppKit handles — once built they cross threads, outlive the view, and
encode off-main. Node-id stringification of each item and deterministic JSON
rounding of the raw `Double`s are downstream (`FlexScopeCore`) concerns, not this
layer's.

## `ViewSnapshot` / `WindowSnapshot` — the live view tree

`AppKitWalker` is the aggregator: `@MainActor` entry points walk a live tree and
compose the leaf snapshots into a recursive `ViewSnapshot`.

- **`snapshot(view:inWindow:maxDepth:)`** projects a view subtree. Each node
  carries its real `runtimeClass` and `superclasses` chain, the raw bottom-left
  `frame` **and** the window-normalized top-left `frameTopLeft` with `isFlipped`
  (the coordinate flip — AppKit's bottom-left origin reconciled to a top-left rect
  relative to the window; with no window it falls back to the raw frame),
  `hidden`/`alpha`, `identifier`/`text`/`axRole`, the composed
  `font`/`material`/`blendingMode`/`layer`/`constraints`, the `swiftUIBoundary`
  flag (true when any class in the runtime superclass chain contains
  `NSHostingView`), and `childCount`/`truncated`/`children`. The walk is
  depth-bounded and carries a visited set so a cycle cannot loop. An unbacked view
  (`view.layer == nil`) gets `layer == nil`, not a `present:false` stand-in.
- **`snapshotApplicationWindows(maxDepth:)`** snapshots every root `NSApp` window
  (no parent, no sheet parent). An attached sheet or ordered child window is
  **nested under its parent** in `WindowSnapshot.childWindows` — deduped against an
  app-wide visited set — rather than dropped or surfaced as a stray root.
- **`snapshotForHitTest(at:inWindow:)`** returns the deepest view at a window-base
  point as a single childless node.

## `LayerSnapshot` — one CALayer

A `CALayer` flattened to plain data: `present`, the geometry/compositing scalars,
the baked sRGB hex of each `CGColor` (via `NSColor(cgColor:)` →
`usingColorSpace(.sRGB)`, `nil` on an unconvertible pattern color), and
`sublayers` bounded at depth 64. A **nil** layer yields `present == false`.
CALayer's real defaults are reported as read — `backgroundColor` is nil but
`borderColor`/`shadowColor` default to opaque black (`#000000FF`).

## Acceptance

- `[scenario.runtime.walker.color-srgb]` An `NSColor(srgbRed:green:blue:alpha:)`
  round-trips to its exact `#RRGGBBAA` hex (e.g. opaque red → `#FF0000FF`).
- `[scenario.runtime.walker.color-catalog]` A catalog color (`.labelColor`)
  resolves without crashing — reporting its `catalogName` and a resolved hex,
  never throwing an uncatchable ObjC exception off an unguarded accessor.
- `[scenario.runtime.walker.color-appearance]` The supplied appearance's name is
  recorded in `appearanceName`, and the catalog color is resolved under it.
- `[scenario.runtime.walker.font-system-bold]` `NSFont.systemFont(ofSize: 13,
  weight: .bold)` snapshots to `size == 13`, a non-empty `family`, `weightName ==
  "bold"`, and the `bold` symbolic trait present.
- `[scenario.runtime.walker.font-weight-bucket]` A system font at each
  `NSFont.Weight` snapshots to the matching named bucket.
- `[scenario.runtime.walker.font-raw-weight-trait]` The `weightTrait` is the raw
  CoreText value out of the descriptor, carried at full precision — not the 1–14
  `NSFontManager` weight.
- `[scenario.runtime.walker.font-traits]` A monospaced system font surfaces
  `monoSpace` in `traits`.
- `[scenario.runtime.walker.width-constraint]` Snapshotting a view with an
  activated `widthAnchor` equal-to-constant 100 yields a `ConstraintDescription`
  with `first.attribute == "width"`, `relation == "equal"`, `constant == 100`,
  `multiplier == 1`, `isActive == true`, and `first.isTarget == true`.
- `[scenario.runtime.walker.constant-constraint]` A constant (single-item)
  constraint's `second` has `className == nil`, `kind == "none"`, and
  `attribute == "notAnAttribute"`.
- `[scenario.runtime.walker.intrinsic-default]` A plain `NSView` with no intrinsic
  content size reports `intrinsicContentSize.width/height == -1`
  (`NSView.noIntrinsicMetric`), carried raw.
- `[scenario.runtime.walker.sizing-defaults]` A freshly built `NSView` reports its
  AppKit-default content-hugging and compression-resistance priorities on both
  axes.
- `[scenario.runtime.walker.constraint-dedup]` A constraint reachable from both
  the view and an ancestor appears exactly once in `constraints`.
- `[scenario.runtime.walker.ancestor-touch]` A constraint held by an ancestor that
  references the target view is collected; an ancestor constraint touching only
  the target's siblings (not the target) is excluded.
- `[scenario.runtime.walker.constraint-real-class]` `ConstraintItem.className` is
  the runtime class name from `object_getClass`, not the static Swift type name.
- `[scenario.runtime.walker.real-class]` Each view node's `runtimeClass` is the
  runtime ISA (`object_getClass`), e.g. `NSVisualEffectView`, not the static type.
- `[scenario.runtime.walker.coordinate-flip]` A view reports its raw bottom-left
  `frame` and a normalized top-left `frameTopLeft`; a view whose `isFlipped` is
  true still normalizes correctly; with no window `frameTopLeft` falls back to the
  raw frame.
- `[scenario.runtime.walker.depth-truncation]` A small `maxDepth` sets
  `truncated == true` and omits deeper children while still reporting `childCount`.
- `[scenario.runtime.walker.swiftui-boundary]` An `NSHostingView` in the class
  chain sets `swiftUIBoundary`; a plain AppKit view does not.
- `[scenario.runtime.walker.unbacked-layer]` A view with `wantsLayer == false`
  carries `layer == nil`, not a `present:false` stand-in.
- `[scenario.runtime.walker.child-window-nesting]` An attached child window appears
  only nested under its parent's `childWindows`, never as a top-level root.
- `[scenario.runtime.walker.layer-defaults]` A default `CALayer` reports
  `backgroundColor == nil` but `borderColor`/`shadowColor == "#000000FF"`.
- `[scenario.runtime.walker.layer-depth]` A `CALayer` sublayer tree is bounded at
  depth 64.
