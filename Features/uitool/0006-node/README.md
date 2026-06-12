# 0006 — Single-node deep read

The `uitool node` verb: read one already-located node deeply, pulling the on-demand projections (`class`/superclasses, `frame`, `constraints`) that the default tree projection omits or summarizes. This is the **drill** step in the canonical loop — locate few → project narrow → **read deep on the survivors** — so it operates on a single node id the agent already chose, not the tree.

Depends on [[domain.uitool.node]] (the field shapes it projects), [[domain.uitool.node-id]] (the `--at` handle it resolves), and [[domain.uitool.ipc]] (the op it issues — `hierarchy` at `maxDepth: 0` — and the exit codes it maps). As a post-attach query verb it never surfaces the attach-time precondition exit code, so it does not depend on [[domain.uitool.injection]].

`node` is part of the **cheap-read MVP** (windows/tree/find/node): its default projection and the structural `--include` facets (`class`/superclasses, `frame`, `constraints`) are bounded, no-invoke reads built on the pure `UIToolCore`. The value-fetching facets (`ivars`, `props`) are **deferred to the injection / expensive-verb half** and are not available in this build — they are documented here, not silently dropped.
