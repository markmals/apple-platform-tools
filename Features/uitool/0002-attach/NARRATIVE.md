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

Three commands. **Attach** reaches into an already-running target and makes it inspectable without restarting it, so the app stays exactly as it sits right now — the research default. **Launch** starts a target fresh with the inspector already loaded, for when a clean state is wanted (or the app is not running yet); it gives up whatever was on screen in any prior instance. Once the app is inspectable — by either route — every later query in the session targets it through a private channel scoped to that one app. **Detach** ends the session and lets the app run normally again. Asking to attach an app that is already attached simply confirms it is attached; asking to detach one that is not attached simply confirms it is detached; a launch always starts a new instance, so it always begins a new session. Each fresh attach or launch starts a new session, so handles from a previous session are recognizably stale rather than silently wrong.

Both launch and attach have **two postures**, set by what the target is rather than by a flag — and `doctor` is where the agent learns which one is available before it tries. In the **cooperative** posture, the target is an app the researcher built and signed for development: it carries the debug opt-in, so launch and attach both succeed on a stock, SIP-enabled Mac with no machine-wide changes — the common case, and the one to reach for first. In the **unrestricted** posture, the target is an app the researcher did *not* sign — a system app, a notarized third-party app — which ships hardened with no per-app opt-in; reaching a *running* one without restarting it requires a deliberately defanged dev box and is the deferred hard part. Either posture, the command reports what it actually did so the agent never has to guess which one it got.

## Why this matters

The whole tool is gated on this step. If attach is unreliable or its failures are mute, the agent wastes turns guessing why later queries return nothing. By making attach report exactly what it did — which path it took, that the channel is open, which session this is — and making every failure name its cause and a recovery, the agent spends its budget on the actual research question, not on the plumbing.

## What this is NOT

This is not querying the view tree — no windows, nodes, fonts, or layers are read here (those are later features). It is not the environment check that decides whether injection is even possible (that is `doctor`). And it ships no write or mutation capability; v1 is read-only.
