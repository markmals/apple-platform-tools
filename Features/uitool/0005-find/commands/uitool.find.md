---
id: command.uitool.find
kind: command
depends-on: [domain.uitool.selector, domain.uitool.node-id, domain.uitool.node, domain.uitool.ipc]
status: draft
---

# `uitool find` — locate few

<!--
  The cheap "locate few" entry point of the canonical loop. Resolves a class
  selector and/or a --where predicate server-side, optionally counts, caps, and
  projects, then emits only the matched nodes. Pure-core decision logic the CLI
  wraps; testable without injection by feeding it captured match data.
-->

## Synopsis

```
uitool find <app> [--class GLOB] [--where EXPR] [--fields PATHS] [--limit N] [--count-only]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<app>` | string | yes | the attached target — pid or bundle id (e.g. `com.apple.mail`) |
| `--class` | string (glob) | no | a bare **class glob** per [[domain.uitool.selector]]; class matching honors the runtime class hierarchy. `--class` accepts a class glob only — the richer structural combinators (descendant, child, attribute) live in `--where`, not here. The two flags compose: `--class` narrows by class, `--where` adds predicate constraints over the survivors. |
| `--where` | string (predicate) | no | a predicate expression per [[domain.uitool.selector]] (total, bounded; `and`/`or`/`not`, `matches`, `intersects`, `~`). A `matches`/`~` operand is a **Swift-native `Regex`** — case-insensitive, unanchored substring (`firstMatch`); an invalid pattern throws at construction and surfaces as a usage error (exit 2, see [[error.uitool.find-bad-selector]]), never a hang or a silent zero-match. |
| `--fields` | string | no | projection path list per [[domain.uitool.selector]] (`node,class,frame,font`); ignored when `--count-only`. When omitted, `find` emits the **full default node projection** from [[domain.uitool.node]] (the default field set: `node`, `class`, `frame`/`frameTopLeft`/`isFlipped`, and the other default fields that model defines) — not a `find`-specific minimal default. The HANDOFF examples pass `--fields` explicitly because narrow projection is the cheaper habit, but the default is the full node projection, so an agent that omits the flag still gets a complete, well-defined record. |
| `--limit` | int | no | cap on returned node records; does not affect the reported total matched count. **Default: 50.** Override with `--limit N` to widen or tighten the cap. Pair with `--count-only` first to size a query before paying for the records. |
| `--count-only` | flag | no | report only the total matched count; return no node records. The cheapest sizing call — "size it before you pay." |

At least one of `--class` / `--where` is required. `find <app>` with neither is a **usage error** (exit 2, see [[error.uitool.find-bad-selector]]): an unconstrained full enumeration is exactly the expensive tree-download the cost-tiering exists to discourage, so the surface refuses it rather than silently matching every node. To enumerate broadly on purpose, pass an explicit broad selector (e.g. `--class '*'`) and size it with `--count-only` first.

## Behavior

1. Resolve `<app>` to the attached session; if no session is attached, fail (exit 4 per [[domain.uitool.ipc]]).
2. Require at least one of `--class` / `--where`; neither present is a usage error (exit 2, see [[error.uitool.find-bad-selector]]).
3. Parse `--class` and/or `--where` into the selector / predicate per [[domain.uitool.selector]]; a parse failure — an unknown combinator, an unbalanced bracket, or an **invalid `Regex` pattern in a `matches`/`~` operand** — is a usage error (exit 2, see [[error.uitool.find-bad-selector]]).
4. Issue the matching op (`find`) to the injected server, which evaluates the selector / predicate **server-side** against the live tree on the target's main thread (per [[domain.uitool.ipc]]); only matching nodes cross the wire.
5. If `--count-only`: emit the total matched count in `_meta.totalMatched`; return no records.
6. Otherwise: project each matched node to `--fields` per [[domain.uitool.node]] (or the full default projection when `--fields` is omitted), cap to `--limit` (default 50), emit the records, then emit the result-summary `_meta` marker (per [[domain.uitool.ipc]]'s envelope).

## Output

Responses conform to [[domain.uitool.ipc]]'s envelope. Every payload — every JSON-Lines object, including each node-record line — carries `schemaVersion` (a semver **string**, e.g. `"1.0.0"`, per [[domain.uitool.ipc]]). Unless `--no-meta` is passed, the response also carries a top-level `sessionId` (string) and, on the streamed result, a `_meta: {returned, truncated, totalMatched}` summary; `--no-meta` strips both `sessionId` and `_meta` (never `schemaVersion`).

`sessionId` appears **once per response, on the summary line** — the single `--count-only` object, or the trailing `_meta` line of the multi-record stream — not repeated on every node-record line. A node-record line carries its `schemaVersion` and projected fields only; the session is identified once for the whole stream.

`--count-only` — a single JSON object carrying the match count in `_meta.totalMatched`, with no node records:

```jsonc
{"schemaVersion":"1.0.0","sessionId":"a1b2c3","_meta":{"returned":0,"truncated":false,"totalMatched":3}}
```

Otherwise — JSON-Lines: one matched node per line (projected to `--fields`, fields from [[domain.uitool.node]]), then a final `_meta` line carrying the per-stream `sessionId`:

```jsonc
{"schemaVersion":"1.0.0","node":"7:w0/cv/sv0/tv0/tr0/c0#b2c4","class":"NSTextField","frame":{"x":34,"y":8,"w":160,"h":16},"font":{"family":"SF Pro Text","size":13,"weightName":"regular"}}
{"schemaVersion":"1.0.0","sessionId":"a1b2c3","_meta":{"returned":1,"truncated":false,"totalMatched":1}}
```

- One node per line so the agent consumes incrementally and a truncated read still yields N valid records (per [[domain.uitool.ipc]] / HANDOFF §8.1).
- `_meta.returned` = records emitted; `_meta.truncated` = true when `totalMatched > returned` because of `--limit` (the single canonical "more exist" flag per [[domain.uitool.ipc]] — never a second `limitHit`); `_meta.totalMatched` = the full server-side match count regardless of `--limit`.
- Deterministic: stable key order, children/records in z-order (never address order), frames to 1 dp, no addresses/timestamps in the default projection. `pointer` is a pull-on-demand field, never a sort key (see [[domain.uitool.node-id]]).
- `--no-meta` strips the summary line's `sessionId` and the `_meta` summary for byte-identical diffs across sessions, but never `schemaVersion` (which is in every payload per [[domain.uitool.ipc]]).

## States & exit codes

Mapped to [[domain.uitool.ipc]]'s exit-code table.

| State | Exit | stdout / stderr |
| --- | --- | --- |
| success (≥1 match, or any `--count-only`) | 0 | payload on stdout |
| valid query, 0 matches | 0 | empty result on stdout, `_meta.totalMatched: 0` (a 0-match query is **not** an error per [[domain.uitool.ipc]]) |
| malformed selector / predicate, or neither `--class` nor `--where` given | 2 | structured error on stderr (see [[error.uitool.find-bad-selector]]) |
| not attached | 4 | structured error on stderr (see [[error.uitool.find-not-attached]]) |
| socket / main-thread timeout | 7 | structured error on stderr (see [[error.uitool.find-timeout]]) |
| schema-version mismatch | 8 | structured error on stderr (defined by [[domain.uitool.ipc]]'s exit-code table; not a find-specific error) |

## Invariants

- Read-only and side-effect-free; idempotent — re-running with the same target state yields byte-identical output (modulo the suppressible `sessionId`).
- Filtering and projection happen **server-side**; the CLI never pulls the tree to filter or project locally (per [[domain.uitool.selector]]).
- Never exits 0 on failure. A valid 0-match result is distinct from a usage error (exit 2) — re-issuing the same query is the wrong recovery for a 0-match.
- `--count-only` reports `totalMatched` unaffected by `--limit`; with records, `_meta.totalMatched` likewise reflects all matches, not just the returned slice.
- Class predicates resolve through the runtime class hierarchy, not string equality (per [[domain.uitool.selector]]).
- Predicate `matches`/`~` operands evaluate as Swift-native `Regex` (case-insensitive, unanchored substring); an invalid pattern is rejected at parse time (exit 2), never deferred to a partial result.
- Evaluation is total and bounded — no selector or predicate can hang the target (per [[domain.uitool.selector]]); exceeding the main-thread budget yields exit 7, not a hang.

## Notes

- **Cost tier: cheap / bounded.** `find --count-only` is the cheapest sizing call; `find --where … --limit N --fields …` is bounded by `--limit` (default 50) and the projection. This is the first verb the Skill steers toward — locate few → project narrow → read deep on the survivors. The expensive deep-read verbs (`node`, `font`, `layer`, `constraints`) then operate on the 1–3 survivors `find` returns.
- Batching: large inputs are stdin JSON-Lines elsewhere in the surface (per HANDOFF §8.5). `find` itself is single-query per spawn — one `--class`/`--where` per process — in this build; stdin batching of selectors/predicates is reserved for the node-resolution verbs, where a batch of stable handles is the natural unit.
