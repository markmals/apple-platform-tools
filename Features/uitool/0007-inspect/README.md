# 0007 — Inspect a live object

The first **value-fetching** verb — reading what's *inside* an object, past the
structural surface the cheap-read verbs (`windows`/`tree`/`find`/`node`) report.

- **[[command.uitool.inspect]]** — `uitool inspect <app> --at <node-id>` reports a
  live object's **ivar values** (safe memory reads, the default) and its **class
  reflection** (declared properties, methods, protocols). `--invoke` additionally
  reads **property values** from the getters — gated, because invoking a getter runs
  the target's own code; it is timed (~500 ms main-thread bound) and safety-screened.
  `--match <regex>` narrows a sprawling object to the fields of interest.

What makes it possible, and the design decisions pinned in this folder:

- **[[domain.uitool.registry]]** — the server-side node-id → live-object map. The
  cheap-read verbs ship plain `Capture` snapshots; `inspect` must reach the *actual*
  `NSObject`, so the server keeps a weak (unretained) registry and resolves a node id
  through a four-gate validation (epoch, structural path re-walk, pointer validity,
  class echo) before any dereference. A stale handle is `STALE_NODE` (exit 5), never a
  recycled-pointer read.
- **Getter safety** ([[domain.uitool.ipc]], reconciled): ivar reads run no target
  code and are default; getter invocation is `--invoke`-only, main-thread, bounded,
  and screened by `RuntimeSafety`. Setters / arbitrary-method invocation / mutation
  stay out of scope — v1 is read-only.
- **Determinism**: values carry no raw pointers and no invoked `-description`; an
  object-typed value is its runtime class (plus a node id when it's a registered
  view). Raw pointers are `--fields pointer` only.

Builds on [[domain.runtime.reflection]] (the already-ported `RuntimeMirror` /
`RuntimeIvar` / `RuntimeProperty` / `RuntimeSafety`), [[domain.uitool.node-id]] (the
id scheme + the validation contract the registry realizes), and
[[error.uitool.node-value-timeout]] / [[error.uitool.node-stale]] (the failure
modes). The structural facets `inspect` complements (`font`/`layer`/`constraints`)
are already served by `node`/`tree`/`find --include`.
