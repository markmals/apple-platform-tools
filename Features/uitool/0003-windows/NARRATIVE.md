---
id: narrative.uitool.windows
kind: narrative
---

# Top-level windows

## Who this is for

A coding agent reverse-engineering a shipping Apple app — and the human researcher behind it who wants to understand how a first-party macOS app builds its interface. The agent drives `uitool`; the human reads the agent's findings and steers the investigation.

## The situation today

Once the agent has attached to a running target, it faces a live object graph it cannot see. It needs an entry point — a small, cheap answer to "what windows does this app have open right now, and which one is the user looking at?" — before it can justify pulling any view tree. Accessibility dumps blur this: they flatten panels, sheets, and the main window into one role-tagged soup and never tell the agent which window is key or main. Asking the agent to download a whole hierarchy just to find the windows wastes its context budget and tells it nothing about focus.

## What we're building

A way for the agent to list the target's top-level windows in one bounded call. For each open window it learns a stable handle it can drill into later, the window's title, its on-screen geometry, and whether that window is currently key (receiving keyboard input) or main (the app's primary window). The list is the natural first move of every session: it is small enough to never threaten the context budget, deterministic enough that the agent can cache and diff it across turns, and rich enough to pick which window to investigate next.

## Why this matters

The agent stops guessing where to look. Instead of a blind tree download, it gets an index of windows, picks the one that matters — usually the key or main window — and spends its budget drilling there. The human researcher gets an immediate, legible map of the app's window surface, including utility panels and sheets the AX tree would have hidden.

## What this is NOT

This is not a view-tree walk: it returns window roots, not their descendants. It does not project fonts, layers, or constraints — those are per-node verbs on a window the agent has already chosen. It does not enumerate off-screen, internal, or system-owned windows beyond what the contract pins.
