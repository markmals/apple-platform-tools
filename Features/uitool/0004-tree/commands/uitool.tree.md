---
id: command.uitool.tree
kind: command
depends-on: [domain.uitool.node, domain.uitool.node-id, domain.uitool.selector, domain.uitool.ipc]
---

# `uitool tree` — depth-bounded hierarchy walk

The structural-exploration verb. Walks the view hierarchy from a chosen root
down a finite depth, projects a chosen set of fields per node, and emits an
explicit truncated marker at every branch cut off by the depth limit. It never
walks the whole tree — `--depth` is always finite and small by default. The
coding agent is the consumer; output is machine-first.

## Synopsis

```
uitool tree <app> [--at NODE] [--depth N] [--fields a,b,c] [--where EXPR] [--limit N] [--count-only] [--jsonl]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | target selector — pid or bundle id of an attached app |
| `--at` | string | no | node id ([[domain.uitool.node-id]]) to root the walk at. Default: when `--at` is omitted, the walk roots at the target's **key window** — the same root the IPC `hierarchy` op selects for `window:"auto"`. A target with no key window (no front window, fully backgrounded) yields an empty walk (exit 0, `_meta.totalMatched: 0`), not an error. To walk a specific non-key window, pass its window-root node id (from a prior `windows` call) as `--at`. |
| `--depth` | int | no | levels to descend below the root, inclusive of the root level. Default: **2**. This is the Skill-steered structural-skim depth (`tree --depth 2`); deeper walks are an explicit, costed choice. `--depth` is always finite — there is no "walk everything" value. |
| `--fields` | string | no | comma-separated projection paths (e.g. `node,class,frame`), as defined by [[domain.uitool.node]]'s dotted field projection. Default: the default projection from [[domain.uitool.node]] |
| `--where` | string | no | server-side filter expression ([[domain.uitool.selector]]) applied to nodes within the depth window. The predicate selects which nodes are **emitted**; it does not prune the walk. A node that fails `--where` is omitted from the result, but the walk still descends into its in-window descendants and emits any of them that match — a deep match is never hidden behind a shallow non-match. Parent linkage in emitted records refers to the nearest *emitted* ancestor; when an intermediate ancestor was filtered out, its `parent` is the nearest surviving ancestor within the depth window (and is absent for the walk root). A `--where` expression that does not parse is a `BAD_PREDICATE` error (exit 2) before any walking begins — see [[error.uitool.tree-bad-projection]]. |
| `--limit` | int | no | maximum number of node records to emit; the walk stops once reached. Default: **50**. The default exists so an unexpectedly wide level can never flood the agent's context; raise it deliberately with `--limit N` when a known-wide level must be read whole. A walk stopped by `--limit` sets `_meta.truncated: true`. To size a query before paying for it, use `--count-only`. |
| `--count-only` | flag | no | size the query without transferring node bodies: run the walk + `--where` filter server-side and return only the envelope (`schemaVersion`, `sessionId`, `_meta`) with `_meta.totalMatched` set to the number of nodes the walk matched within the depth window. No node records cross the wire. Use it to decide whether to widen `--limit`, tighten `--where`, or descend a different branch before paying for the bodies. |
| `--jsonl` | flag | no | explicit opt-in to the JSON-Lines stream output shape. **JSON-Lines is already the default for `tree`** (it is a list/stream verb), so `--jsonl` is a no-op kept for symmetry with the other stream verbs and for callers that want to state the shape explicitly. `tree` never emits a single nested object; the wire shape is always one node record per line followed by the trailing envelope line. |

## Behavior

1. Resolve `<app>` to the attached target's socket; if there is no live session
   (never attached, or the session has gone away), this is exit 4 — not a
   precondition failure (preconditions are attach-time only, see States & exit
   codes).
2. Resolve `--at` to a live object: re-walk the structural path and validate per
   [[domain.uitool.node-id]]'s deref rules. On any mismatch, return `STALE_NODE` —
   never dereference a recycled pointer. When `--at` is omitted, the root is the
   target's key window (`window:"auto"`), resolved the same way.
3. Issue the [[domain.uitool.ipc]] `hierarchy` op with `maxDepth` from `--depth`, the
   resolved root, and `include` derived from `--fields`. Filtering and projection
   happen **server-side, in the injected agent** — only the projected, in-window,
   matching nodes cross the wire.
4. The server walks each node down to `maxDepth`. At a node that has children but
   sits at the depth limit, it emits `truncated: true` and `childCount` and omits
   `children` — the depth-cut marker contract defined by [[domain.uitool.node]] (its
   `children` field is present only within `--depth`; past it, omitted with
   `truncated: true` + `childCount`).
5. Apply `--where` to select which walked nodes are emitted; a non-matching node
   is dropped from the result but its in-window descendants are still walked and
   emitted on their own merits.
6. Project each emitted node to the requested `--fields`; `node` is always
   present so the agent can drill in later.
7. Emit the result, stopping at `--limit`. A capped result sets
   `_meta.truncated: true` ([[domain.uitool.ipc]]'s single canonical "more exist" flag).
   Under `--count-only`, steps 6–7 are skipped: no node bodies are emitted, only
   the envelope with `_meta.totalMatched`.

## Output

Each node follows [[domain.uitool.node]] — same field semantics, same precision, same
truncated-marker shape. The agent uses each node's `node` handle to issue
follow-up `node` calls on survivors.

`tree` emits a **JSON-Lines stream**: one node record per line, in walk order,
followed by a single trailing envelope line. The agent consumes incrementally,
and an interrupted read still yields N whole, valid node records up to the cut.
This is the contracted wire shape (`--jsonl` is the explicit, no-op opt-in to
it); `tree` never emits a single nested object.

```jsonc
{"node":"7:w0/cv/sv2","parent":"7:w0/cv","class":"NSScrollView","frame":{"x":0,"y":0,"w":280,"h":600},"childCount":1}
{"node":"7:w0/cv/sv2/sub0","parent":"7:w0/cv/sv2","class":"NSClipView","childCount":1,"truncated":true}
{"schemaVersion":"1.0.0","sessionId":"7","_meta":{"returned":2,"truncated":true,"totalMatched":2}}
```

The trailing envelope line conforms to [[domain.uitool.ipc]]'s envelope — a top-level
`schemaVersion` (semver string, in *every* payload and never stripped), a
top-level `sessionId` (string), and, on this list/stream verb, `_meta:
{returned, truncated, totalMatched}`; `--no-meta` strips `sessionId` and `_meta`
but not `schemaVersion`:

- A node cut off by `--depth` carries `truncated: true` + `childCount` and omits
  `children`. A node whose whole subtree is within `--depth` is never marked
  truncated.
- `_meta.returned` is the node count emitted; `_meta.totalMatched` is the count
  of nodes the walk matched within the depth window (0 for an empty walk). Under
  `--count-only`, `_meta.returned` is 0 and `_meta.totalMatched` carries the full
  matched count.
- `_meta.truncated` — the single canonical "more exist past the limit/depth"
  flag — is true if any branch was depth-cut or if `--limit` stopped the walk.
- Output is deterministic per [[domain.uitool.node]]'s determinism invariant: stable key
  order, children in subview / z-order, frames to 1 dp, no addresses/timestamps in
  the default projection (modulo the suppressible top-level `sessionId`).

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table. `tree` is a **post-attach query
verb**, so it carries neither exit 3 (app not running) nor exit 6 (precondition)
— both are attach-time only, emitted while `doctor` / `list-apps` / `attach`
resolve and inject. An unreachable session surfaces here as exit 4 (not
attached) or exit 7 (timeout), never 3 or 6.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (including a fully-contained tree, a depth-truncated tree, a `--count-only` sizing, and a walk that contains zero nodes) | 0 | the payload on stdout |
| usage / unknown `--fields` path (`UNKNOWN_FIELD`) / malformed `--where` predicate (`BAD_PREDICATE`) | 2 | structured error on stderr — see [[error.uitool.tree-bad-projection]] |
| not attached / injection failed (or a session that has gone away post-attach) | 4 | structured error on stderr |
| `--at` handle is stale | 5 | structured error on stderr — see [[error.uitool.tree-stale-root]] |
| main-thread snapshot timed out | 7 | structured error on stderr |
| schema-version mismatch | 8 | structured error on stderr |

A valid walk that matches/contains zero nodes (an empty subtree, a target with
no key window, or a `--where` that excludes everything) is **exit 0**, not an
error — the response carries an empty stream and `_meta.totalMatched: 0`. The
agent distinguishes empty from error by reading `_meta`, never by the exit code;
a 0-match result means *broaden the selector*, not re-issue. See
[[domain.uitool.ipc]].

## Invariants

- Read-only and side-effect-free; idempotent. Same target state → byte-identical
  output (modulo the suppressible `sessionId`).
- `--depth` is always finite; the command never walks the whole tree regardless
  of input.
- Every emitted node carries its `node` handle even under the narrowest `--fields`.
- A depth-cut node is always distinguishable from a leaf: `truncated: true` +
  `childCount > 0` vs `childCount: 0` (a leaf is never marked truncated).
- Never exits 0 on failure; a stale `--at` is exit 5, never a silent empty tree.
- A truncated read (process killed mid-stream) still yields whole, valid node
  records up to the cut — a property of the JSON-Lines wire shape.
- `--count-only` transfers no node bodies; it returns only the envelope and is a
  strict subset of a full walk's work (same matched count, no projection cost).

## Notes

- **Cost tier: cheap / bounded.** This is one of the read verbs the Skill steers
  toward (`tree --depth 2`); the per-node deep reads (the `node` verb's expensive
  facets — ivars, props) are the costed follow-ups on a single chosen survivor.
  The whole point is tree *search*, not tree *download*.
- Cost scales with `--depth` and subtree fan-out; pair with `--fields` to keep a
  structural skim tiny, `--limit` to cap an unexpectedly wide level, and
  `--count-only` to size a query before paying for the bodies.
- **No stdin batching.** `tree` walks a single root per spawn; batching multiple
  roots through stdin is reserved for the per-node `node` verb (its `--stdin`
  mode). A multi-branch exploration issues one `tree` per branch, each rooted by
  `--at` on a handle from the prior walk — which is exactly the bounded,
  one-branch-at-a-time access pattern this feature exists to make cheap.
