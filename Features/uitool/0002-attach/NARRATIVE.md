---
id: narrative.uitool.attach
kind: narrative
---

# Inject & detach

## Who this is for

A coding agent reverse-engineering how Apple's first-party Mac apps are built — and the human researcher behind it who wants to reproduce that look-and-feel in native AppKit. Before the agent can ask a single question about a running app's view tree, it needs that app to be inspectable. This feature is that first move.

## The situation today

The agent can see what Accessibility exposes, but Accessibility hides the very things the researcher cares about: the real runtime classes, exact frames, resolved fonts, layer fills. Getting a richer view requires getting an inspection bridge running inside the target process, and that is fiddly, easy to get silently wrong, and unfamiliar to an agent driving a CLI. The agent needs one dependable verb that says "make this app inspectable" and another that says "let it go", with results it can branch on without reading prose.

## What we're building

Two commands. The first takes a target app and makes it inspectable, by default by attaching to the already-running process so the app stays exactly as it sits right now — or, when a clean-launch state is wanted, by relaunching it under inspection (which gives up the app's current on-screen state). Once the app is inspectable, every later query in the session targets it through a private channel scoped to that one app. The second command ends the session and lets the app run normally again. Asking to attach an app that is already attached simply confirms it is attached; asking to detach an app that is not attached simply confirms it is detached. Each fresh attach starts a new session, so handles from a previous session are recognizably stale rather than silently wrong.

## Why this matters

The whole tool is gated on this step. If attach is unreliable or its failures are mute, the agent wastes turns guessing why later queries return nothing. By making attach report exactly what it did — which path it took, that the channel is open, which session this is — and making every failure name its cause and a recovery, the agent spends its budget on the actual research question, not on the plumbing.

## What this is NOT

This is not querying the view tree — no windows, nodes, fonts, or layers are read here (those are later features). It is not the environment check that decides whether injection is even possible (that is `doctor`). And it ships no write or mutation capability; v1 is read-only.
