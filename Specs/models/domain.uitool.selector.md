---
id: domain.uitool.selector
kind: domain
depends-on: [domain.uitool.node]
---

# Selector & Predicate Grammar

The two server-side query languages for `find` / `--where`. Both are evaluated **inside the injected process** against the live tree, so only matching nodes cross the wire — for a 10k-node window the agent cannot afford to pull the tree and grep locally. Derived from HANDOFF §8.3.

## CSS-like structural selectors

| Form | Meaning |
| --- | --- |
| `NSButton` | by class — **honors the runtime class hierarchy** (`NSControl` matches `NSButton`) |
| `NSScrollView NSTableView` | descendant |
| `NSStackView > NSTextField` | direct child |
| `NSView[title*="Inbox"]` | attribute substring |
| `NSView[frame-w>200]` | geometry predicate |
| `*[hidden=false]` | wildcard + attribute |

Class matching honoring the **runtime hierarchy** (`classHierarchyOfObject:` / `subclassesOfClassWithName:`) is the capability AX fundamentally cannot offer (AX has roles, not classes) — the headline reason the tool exists.

## Predicate expression language (`--where`)

A tiny **total** language — comparisons, `and` / `or` / `not`, `matches`, `intersects`, `~` (class-of). **No recursion, bounded evaluation time**, so a query can't hang the target.

```
class ~ 'NSTextField' and text *= 'Inbox'
frame-w > 200 and hidden = false
```

## Field projection (`--fields`)

A projection **path list** (`class,frame,font.family`), NOT full jq. Full jq is a footgun (non-deterministic ordering, unbounded output) and is deliberately excluded.

## The matching engine

`*=` (substring) and `matches` (regex) — plus `[attr*="…"]` in the structural form — are backed by Swift's **native `Regex`** (Swift 5.7+; the package's macOS 14 floor guarantees it), **not** `NSRegularExpression`. The contract:

- **Case-insensitive, unanchored substring semantics.** A pattern matches if it occurs *anywhere* in the candidate string — the engine uses `firstMatch(in:)`, not a whole-string anchor, and folds case. `text *= 'inbox'` matches `"Inbox Unread"`; `text matches 'in.ox'` matches the same. To anchor, write the anchors into the pattern (`^Inbox$`).
- **An invalid pattern throws at construction.** A `--where` clause or `[attr*=…]` selector whose regex doesn't compile is a *usage* error, surfaced as the `BAD_SELECTOR` failure (code `BAD_SELECTOR`, **exit 2**) — see [[error.uitool.find-bad-selector]]. The pattern is rejected before any node is touched, so a malformed selector never partially-evaluates against the tree.
- **`*=` is the substring sugar over `matches`.** `text *= 'foo'` is `text matches` a literal-escaped `foo`, so `*=` can never itself be a "bad selector" on metacharacters — only an explicit `matches` regex can throw.

`--class` GLOB matching (the `classes` / structural class-token vocabulary) is **separate** and unchanged: it stays shell-style glob (`NS*View`, `_NSToolbar*`), not regex. Glob and regex do not bleed into each other — `[attr*=…]` / `matches` are regex; `--class` is glob.

## Sizing a query before paying for it

`find` (and `classes`) carry a **`--limit` defaulting to 50** matched nodes and a **`--count-only`** flag. The canonical move is `find --count-only` to learn how many nodes a selector matches (cheap — a count, not a tree), then `find --where … --fields … --limit N` to pull the survivors. `--limit N` overrides the default; `--count-only` returns only the count (`_meta.totalMatched`) and no node bodies. The default cap exists so a too-broad selector against a 10k-node window can never blow the agent's context on the first call — broaden deliberately, raise `--limit` deliberately.

## Invariants

- Evaluation is total and bounded — no construct can loop or recurse unboundedly.
- Class predicates resolve through the runtime class hierarchy, not string equality.
- Filtering and projection happen **server-side**; the CLI never pulls the tree to filter locally.
- Regex matching is case-insensitive, unanchored substring (`Regex.firstMatch`), never `NSRegularExpression`; an uncompilable pattern is rejected at construction as `BAD_SELECTOR` (exit 2), never silently treated as a literal or a zero-match.
- A selector that matches 0 nodes yields a valid empty result — **exit 0** with `_meta.totalMatched: 0` per [[domain.uitool.ipc]] — distinct from a usage error (exit 2). A 0-match means broaden the selector, not re-issue.
- A `--fields` path that names no field on [[domain.uitool.node]] is a usage error (code `UNKNOWN_FIELD`, exit 2); a `--where` predicate the grammar can't parse is a usage error (code `BAD_PREDICATE`, exit 2). The two are **distinct codes**, never collapsed into one "bad projection".

## Relationships

- [[domain.uitool.node]] — the fields selectors match against.
- Consumed by `find`, and the `--where` / `--fields` flags on `tree` / `node`.

## Notes

- The canonical loop: **locate few → project narrow → read deep on survivors** — `find --count-only` to size a selector, then `find --where … --fields … --limit N`, then `node` / `font` / `constraints` on the 1–3 survivors. A few KB per step, never a 200k-token tree dump.
- **v1 attribute vocabulary** (addressable in `[attr…]` selectors and `--where`), all sourced from [[domain.uitool.node]]:
    - `class` (string; `~` resolves the runtime hierarchy), `identifier` (string), `axRole` (string)
    - `text` (string — the view's string value where it has one: `NSTextField.stringValue`, `NSButton.title`, `NSText` string), `title` (string — window / control title)
    - `frame-x`, `frame-y`, `frame-w`, `frame-h` (number, from `frame`)
    - `hidden` (bool), `alpha` (number), `isFlipped` (bool), `swiftUIBoundary` (bool), `childCount` (int), `material` (string, where applicable)

    Operators: `=`, `!=`, `>`, `<`, `>=`, `<=`, `*=` (substring), `~` (class-of / hierarchy), `matches` (regex). The set is intentionally small and additive within a major — new attributes are added deliberately, not ad-hoc.
