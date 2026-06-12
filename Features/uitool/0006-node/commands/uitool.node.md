---
id: command.uitool.node
kind: command
depends-on: [domain.uitool.node, domain.uitool.node-id, domain.uitool.ipc]
---

# `uitool node` — deep-read one located node

The drill step of the canonical loop (locate few → project narrow → **read deep on the survivors**). Reads a single node the agent has already located and pulls the on-demand facets the default tree/find projection omits. It does not walk a subtree and does not search.

## Synopsis

```
uitool node <app> --at NODE [--include class,frame,constraints,layer]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | target selector (pid or bundle id) — the attached session to query |
| `--at` | node id | yes | the [[domain.uitool.node-id]] of the single node to read |
| `--include` | comma list | no | facets to pull beyond the default projection; subset of `class,frame,constraints,layer` in the cheap-read MVP (`ivars`/`props` are deferred — see below). Default: none (default projection only) |

The `--include` tokens map to fields of [[domain.uitool.node]]:

| Token | Adds to the record |
| --- | --- |
| `class` | `superclasses` (the runtime hierarchy; the real `class` is already in the default projection) |
| `frame` | **No-op kept for symmetry.** `frame`, `frameTopLeft`, and `isFlipped` are already default-projection fields of [[domain.uitool.node]] (it never omits frames), so `--include frame` requests nothing new — it is accepted (not rejected as a bad token) and changes nothing in the record. The token exists only so an agent can name `frame` uniformly across verbs without special-casing `node`. |
| `constraints` | **Inlines the full constraint list.** The default projection carries only `constraintsCount`; `--include constraints` inlines the walker's `ConstraintNode` (every touching `NSLayoutConstraint` plus the intrinsic-sizing facts — the same shape the dedicated `constraints` verb returns) into the node record, alongside the still-present `constraintsCount`. |
| `layer` | `layer` (the recursive `LayerSnapshot` where `wantsLayer`; `null` otherwise) |

### Deferred facets (`ivars`, `props`) — not available in this build

`--include ivars` and `--include props` are **value-fetching** facets: they invoke live getters / read instance state **inside the target process**, so they belong to the deferred injection / expensive-verb half (see [[domain.uitool.ipc]] → "Default mode: structural, no-invoke" and HANDOFF §8.2 / §11). They are **not part of the cheap-read MVP** and are **not available in this build**:

- The cheap-read `node` build accepts only the structural tokens (`class`, `frame`, `constraints`, `layer`). Passing `ivars` or `props` is reported as a **not-yet-available facet** — an explicit, structured usage error (exit 2) naming the facet and that it requires the injection half — never a silently-dropped token. The agent learns the facet exists but is not yet served, rather than getting a quietly thinner record than it asked for.
- When the injection half lands, `ivars`/`props` join the `--include` vocabulary as value-fetching facets. They run on the target's main thread under [[domain.uitool.ipc]]'s bounded timeout; on timeout the op returns `TIMEOUT` (see [[error.uitool.node-value-timeout]]). Their inlined shape (a map of name → boxed value) and any `--match REGEX` narrowing are specified with that pass, not here.

The `material`, `blendingMode`, and `font` pull-on-demand handling of [[domain.uitool.node]] is unchanged: `material` and `font` are already default-projection fields; `blendingMode` and the visual-effect specifics are reached through their dedicated verbs, not inlined here, and have no `--include` token on `node`.

## Behavior

1. Resolve `<app>` to the attached session's socket (per [[domain.uitool.ipc]] transport).
2. Validate `--at` is a well-formed node id; reject malformed ids as a usage error (exit 2) before issuing any op.
3. Validate the `--include` tokens. An unknown token, or a deferred value-fetching token (`ivars`/`props`) in this build, is a usage error (exit 2) — the deferred ones name the facet and that it requires the injection half.
4. Issue one [[domain.uitool.ipc]] op to read the single node rooted at `--at`, carrying the requested structural `include` facets. The single-node read is the **`hierarchy` op pinned to `maxDepth: 0`** — `node` binds to the tree/hierarchy op at depth 0 rather than a distinct op (per [[domain.uitool.ipc]]'s operations table), so it reads exactly one node and never its descendants.
5. The injected server resolves and validates the node id before any deref (re-walk path, pointer validity, recorded-class match per [[domain.uitool.node-id]]); on mismatch it returns `STALE_NODE`.
6. (Injection half, deferred) Value-fetching facets (`ivars`/`props`, and any facet that invokes live getters) run on the target's main thread under the bounded timeout from [[domain.uitool.ipc]]; on timeout the op returns `TIMEOUT`. The cheap-read structural facets never invoke getters and never hit this path.
7. Project the one node to [[domain.uitool.node]]'s default fields plus exactly the requested facets, and emit it.

## Output

A single JSON object (scalar query, not JSON-Lines) describing one node, per [[domain.uitool.node]]. Default-projection fields always present; only the requested `--include` facets are added. Deterministic per [[domain.uitool.ipc]]: stable key order, fixed precision, no addresses/timestamps in the default projection.

```jsonc
// uitool node com.apple.mail --at 7:w0/cv/sv2/sub0 --include constraints,layer
{
    "schemaVersion": "1.0.0",
    "sessionId": "7",
    "node": "7:w0/cv/sv2/sub0",
    "parent": "7:w0/cv/sv2",
    "class": "NSVisualEffectView",
    "frame": { "x": 0, "y": 40, "w": 280, "h": 600 },
    "frameTopLeft": { "x": 0, "y": 0, "w": 280, "h": 600 },
    "isFlipped": false,
    "hidden": false,
    "alpha": 1.0,
    "identifier": "MailMessageListSidebar",
    "text": null,
    "axRole": "AXGroup",
    "font": null,
    "material": "sidebar",
    "constraintsCount": 4,
    "swiftUIBoundary": false,
    "childCount": 7,
    "constraints": [
        { "firstItem": "7:w0/cv/sv2/sub0", "firstAttribute": "width", "relation": "==", "constant": 280, "priority": 1000 }
    ],
    "layer": { "present": true, "cornerRadius": 6, "masksToBounds": true, "backgroundColor": "#00000000" }
}
```

Requested facets that do not apply to the node are emitted as `null` (e.g. `layer: null` on an unbacked view, or `font: null` on a node with no font carrier), never omitted — so the agent distinguishes "asked, absent" from "not asked". (`--include frame` is the one exception: a no-op that adds nothing, since the frame fields are already default.)

Per [[domain.uitool.ipc]]'s envelope, the record carries a top-level `sessionId` (string) — the wire form of [[domain.uitool.node-id]]'s `sessionEpoch`, so the agent can detect a re-attach. `node` is a scalar query, not a list/stream verb, so it does **not** carry `_meta` (that envelope key is for list/stream verbs only). `--no-meta` strips `sessionId`, making the output byte-identical across sessions.

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success | 0 | the node object on stdout |
| malformed `--at` / unknown or deferred `--include` token | 2 | structured error on stderr |
| not attached / injection failed (`NOT_ATTACHED`) | 4 | structured error on stderr |
| node id no longer resolves (`STALE_NODE`) | 5 | structured error on stderr (see [[error.uitool.node-stale]]) |
| main-thread / socket timeout on a value-fetching read (`TIMEOUT`) | 7 | structured error on stderr (see [[error.uitool.node-value-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr |

`node` is a post-attach query verb: per [[domain.uitool.ipc]], exit 3 (app not running) and exit 6 (precondition failed) are attach-time only and never surface here. An unreachable session is exit 4 (`NOT_ATTACHED`) or exit 7 (`TIMEOUT`).

## Invariants

- Read-only and side-effect-free for the default projection and the structural facets; idempotent — same target state and same flags yield byte-identical output (modulo the top-level `sessionId` from [[domain.uitool.ipc]]'s envelope, which `--no-meta` strips for byte-identical output across sessions).
- Reads exactly one node — the `hierarchy` op at `maxDepth: 0`. Never emits child node records and never walks a subtree.
- Never exits 0 on failure. A `STALE_NODE` is exit 5, distinct from any success.
- Requested-but-inapplicable facets are `null`, not omitted; unrequested facets are absent, not `null`. `--include frame` is a no-op (the frame fields are already default).
- Value-fetching facets (`ivars`/`props`) are not served in this build and are rejected as a usage error (exit 2), never silently dropped. When served (injection half), they never block the host indefinitely — they are bounded by [[domain.uitool.ipc]]'s main-thread timeout.

## Notes

Cost tier: **cheap/bounded** for the default projection (which already carries `constraintsCount`, `material`, and `font`) and the structural `--include` facets (`class`/superclasses, `frame` no-op, `constraints`, `layer`) — one node, bounded, no-invoke work. **Expensive** for `--include ivars`/`props` (and any facet that invokes live getters): they run code inside the target, are timeout-bounded, and are off by default and deferred to the injection half per HANDOFF §8.2 / §11.

Batching: large id lists go over stdin as JSON-Lines (`uitool node --stdin < ids.jsonl`) so the agent resolves many nodes in one process spawn. With `--stdin` the output is **one JSON object per line (JSON-Lines), one per input id, in input order**, each line carrying that node's record (or a per-line error object for a stale/failed id). A `STALE_NODE` (or other per-id failure) on one id emits a per-line structured error and **continues** the batch rather than aborting it; the process exits **0** when every line was emitted (success or per-line error) and reserves a non-zero exit for a batch-level failure (not attached, schema mismatch, malformed stream). The per-line error object carries the same `code`/`message`/`recover` shape as the single-node stderr error, keyed to its input id, so the agent reconciles results to ids without losing the rest of the batch.
