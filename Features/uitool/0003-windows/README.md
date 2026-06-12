# 0003 — Top-level windows

Covers `uitool windows <app>`: enumerating a target app's top-level `NSWindow`s and emitting, for each, its root node id, title, frame, and key/main status. This is the cheapest entry point into a session — the breadth-first first call an agent makes before drilling into any single window's view tree.

**Depends on:** [[domain.uitool.node]] (the window-root node shape and its fields), [[domain.uitool.ipc]] (the request/response wire contract and exit-code mapping), and transitively [[domain.uitool.node-id]] (the stable id minted for each window root).
