---
id: domain.uitool.node
kind: domain
depends-on: [domain.uitool.node-id, domain.runtime.walker]
---

# Domain: View Node

The canonical agent-facing record for one element of a target app's runtime view
tree — what every `uitool` query verb returns. It is the **projection** of a
`RuntimeKit` `ViewSnapshot` / `WindowSnapshot` (see [[domain.runtime.walker]])
into the JSON record the agent reads: the walker reads the live AppKit object on
the main thread and emits a plain `Sendable` snapshot; `UIToolCore` rounds, key-
orders, and stringifies node ids over that snapshot to produce a `node`. Derived
from HANDOFF §8.4; this is the contract `uitool schema` prints.

> **The walker is the source, the node is the shape.** A `ViewSnapshot` carries
> *raw* values (a `CGFloat` is a `Double` with no rounding, the node id is not
> yet stringified — see [[domain.runtime.walker]]'s purity note). The node is that
> snapshot after `UIToolCore` applies deterministic rounding, stable key order,
> and node-id stringification. No field on the node exists that the walker does
> not supply; this model defines *which* of the walker's fields are projected by
> default and which are pulled on demand.

> **Default projection** = the fields marked ✓ below. The rest are pull-on-demand
> via `--include` or a dedicated verb, so the default node stays small enough to
> stream a 10k-node tree under a context budget.

## Shape

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `node` | string | ✓ | stable id — see [[domain.uitool.node-id]] |
| `parent` | string \| null | ✓ | parent node id; null at a window root |
| `class` | string | ✓ | **real** runtime class — the walker's `runtimeClass` (via `object_getClass`): the private subclass (the whole point vs AX) |
| `superclasses` | string[] | — | the walker's `superclasses` chain up to `NSView`/`NSObject` (`--include`) |
| `frame` | {x,y,w,h} | ✓ | raw `NSView` coords (bottom-left origin), 1 dp |
| `frameTopLeft` | {x,y,w,h} | ✓ | normalized top-left, window-relative |
| `isFlipped` | bool | ✓ | the view's `isFlipped` (the #1 silent-correctness trap) |
| `hidden` | bool | ✓ | `isHidden` |
| `alpha` | number | ✓ | `alphaValue`, 1 dp |
| `identifier` | string \| null | ✓ | `NSUserInterfaceItemIdentifier` if set |
| `text` | string \| null | ✓ | the view's text content where it carries one (label/field/title), null otherwise |
| `axRole` | string \| null | ✓ | cross-reference to the AX dump (`ax-diff`) |
| `font` | Font \| null | ✓ | the walker's composed `FontSnapshot`; null where there's no font carrier |
| `material` | string \| null | ✓ | `NSVisualEffectView.material` where applicable |
| `blendingMode` | string \| null | — | `NSVisualEffectView.blendingMode` (`--include`) |
| `layer` | Layer \| null | — | the walker's `LayerSnapshot` where `wantsLayer`; null otherwise (`--include layer` / `layer` verb) |
| `constraintsCount` | int | ✓ | count only in the node; the full `ConstraintNode` list via `--include constraints` or the `constraints` verb |
| `swiftUIBoundary` | bool | ✓ | true at an `NSHostingView` (the walker sets it when any class in the runtime superclass chain contains `NSHostingView`); below it, class names are SwiftUI internals |
| `childCount` | int | ✓ | number of subviews |
| `children` | ViewNode[] | ✓* | present only within `--depth`; past it, omitted with `truncated: true` + `childCount` |

### Default field set, stated plainly

The default projection — emitted by `windows`, `tree`, `find`, and `node` with
no `--include` — is exactly: **`class`** (via the walker's `runtimeClass`),
**`frame`**, **`frameTopLeft`**, **`isFlipped`**, **`hidden`**, **`alpha`**,
**`identifier`**, **`text`**, **`axRole`**, **`font`** (the composed
`FontSnapshot`, or null), **`material`** (or null), **`swiftUIBoundary`**,
**`childCount`**, and **`constraintsCount`** — alongside the identity fields
**`node`**/**`parent`** and, within `--depth`, **`children`**. Everything else is
`--include`-only:

- **`superclasses`** — the full runtime class chain (`--include superclasses`).
- **`blendingMode`** — `NSVisualEffectView.blendingMode` (`--include`).
- **`layer`** — the full recursive `LayerSnapshot` (`--include layer`, or the
  `layer` verb). The node's default already commits to `material` because a
  visual-effect material is a single cheap scalar a layout reviewer reads
  constantly; the layer subtree is the expensive structure and stays opt-in.
- **the full constraint list** — the node carries only `constraintsCount` by
  default; the walker's `ConstraintNode` (every touching `NSLayoutConstraint`
  plus the intrinsic-sizing facts) inlines only under `--include constraints` or
  the `constraints` verb.

### Font (sub-shape)

The walker's `FontSnapshot`, carried through verbatim (see
[[domain.runtime.walker]]): `family` (string), `size` (number, 1 dp),
`weightTrait` (raw CoreText `NSFontWeightTrait`, −1.0…1.0), `weightName` (nearest
named weight), `postScriptName` (string, e.g. `.SFNS-Regular`), `traits`
(string[] symbolic traits).

> **Never** emit a lossy `NSFontManager` weight (1–14) ↔ `NSFontWeightTrait`
> conversion — they're nonlinear and non-interchangeable. Emit both the raw trait
> and the nearest name (HANDOFF §5.2). The walker already enforces this; the node
> projects both fields unchanged.

### Layer (sub-shape)

The walker's `LayerSnapshot`: `present`, `cornerRadius`, `masksToBounds`,
`backgroundColor`, `borderWidth`, `borderColor`, `shadowOpacity`, `shadowRadius`,
`shadowOffset` ({w,h}), `shadowColor`, `sublayerTransform`, `mask`,
`backgroundFilters`, and `sublayers` (the recursive child layers, bounded at
depth 64 by the walker). The full recursive serialization follows the walker's
`LayerSnapshot` shape ([[domain.runtime.walker]]); a dedicated `layer` verb is
deferred to the expensive-verb pass. The CALayer subtree is a **parallel**
structure cross-linked by node id, never merged into the view tree
(`layer.sublayers ≠ view.subviews`).

## Identity

- `node` (the stable id) identifies an instance within a session — see
  [[domain.uitool.node-id]].
- `class` + `frame` are the human/agent-legible secondary identifiers.

## Invariants

- `class` is the **observed** runtime class, never canonical — it is the walker's
  `runtimeClass` (the runtime ISA via `object_getClass`), and it can shift between
  OS builds; output records the OS build (see [[domain.uitool.injection]]).
- `frame`, `frameTopLeft`, and `isFlipped` are always emitted together; a
  consumer must never infer top-left origin from `frame` alone. The walker
  computes `frameTopLeft` by reconciling AppKit's bottom-left origin to a
  window-relative top-left rect; with no window it falls back to the raw frame.
- `layer` is independent of the view: a null `layer` is normal (`NSView.layer` is
  nil unless `wantsLayer`, and the walker emits `layer == nil` for an unbacked
  view, not a `present:false` stand-in). Never assume view↔layer 1:1.
- Below a `swiftUIBoundary: true` node, fonts/frames/fills are reported
  confidently but class names are **not** asserted to be hand-written AppKit
  controls.
- Default-projection output is deterministic: stable key order, z-order children,
  fixed precision, no addresses/timestamps. The walker carries raw values; the
  determinism (`stableRounded`, key order) is `UIToolCore`'s projection step over
  the snapshot, not the walker's.

## Relationships

- [[domain.runtime.walker]] — the `RuntimeKit` layer this node projects: a node
  *is* a `ViewSnapshot` after `UIToolCore` rounding, key-ordering, and node-id
  stringification.
- [[domain.uitool.node-id]] — the `node`/`parent` id scheme.
- [[domain.uitool.ipc]] — how a node is requested and streamed.
- Consumed by the `windows`, `tree`, `node`, `find`, `font`, `layer`,
  `constraints` commands.

## Notes

- Rendered snapshots are out of scope (HANDOFF §6.3 / ARCHITECTURE → "Out of
  scope").
- `backgroundColor` (and any resolved color) is reported as **both** the resolved
  sRGB hex `#RRGGBBAA` **and** the catalog/dynamic color name where one is
  available (e.g. `controlAccentColor`), plus the appearance context it was
  resolved under (e.g. `NSAppearanceNameDarkAqua`). The hex is the unambiguous
  snapshot; the catalog name is what a native reimplementation actually uses.
  Colors are resolved via the window's `effectiveAppearance` + `usingColorSpace:`
  before components are read. This is exactly the walker's `ColorSnapshot`
  contract (see [[domain.runtime.walker]]); the node carries it unchanged.
