# 0004 — Depth-bounded hierarchy

The `uitool tree` verb: a depth-bounded view/layer hierarchy walk from a chosen root node, with server-side field projection and an explicit truncated marker so a 10k-node window never crosses the wire whole. This is the agent's primary structural-exploration call — bounded by `--depth`, narrowed by `--fields`, rooted by `--at` — and the cheap counterpart to the per-node deep-read verbs.

Depends on [[domain.uitool.node]], [[domain.uitool.node-id]], and [[domain.uitool.ipc]].
