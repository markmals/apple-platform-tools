---
id: narrative.uitool.signing
kind: narrative
---

# Read a target's code signing

## Who this is for

A coding agent (and the researcher behind it) deciding whether — and how — to
inspect a given app. Before `attach` or `launch`, the question is: *can I even get
in?* That answer is written into the target's **code signature**: whether it
carries `get-task-allow`, whether the hardened runtime is on, whether it is
sandboxed, who signed it. `signing` reads that profile so the agent knows the
injection posture before it tries, instead of discovering it from a failed attach.

## The situation today

`doctor` answers "is my *machine* ready?" — but injectability is **per target**, and
the deciding facts live on the target's signature, not the machine. An agent can
shell out to `codesign` and squint at the text, but the facts it actually needs —
is this `get-task-allow`? hardened? sandboxed? — are buried in flags and an
entitlements plist. There is no one verb that reads a target's signature and says,
plainly, what it means for inspection.

## What we're building

One static command, `signing`, that takes a target (a pid, a `.app`, or an
executable path), reads its code signature, and reports the facts that decide
injectability: whether it is signed and by whom, its team, the hardened-runtime and
sandbox flags, and the injection-relevant entitlements (`get-task-allow`, the
debugger entitlement, library-validation and dyld-environment overrides). From
those it derives one plain verdict — **is this target cooperatively injectable?** —
so the agent reads a yes/no, not a flag soup. It does no injection and needs no
attach: it reads the signature off disk (or off the running process's binary).

## Why this matters

The whole runtime cluster turns on the cooperative-vs-unrestricted distinction, and
that distinction *is* the target's signature. `signing` makes it legible: an agent
can triage a list of apps into "I can inspect these on a stock Mac" vs "these need
the defanged box" before spending a single attach on the wrong one.

## What this is NOT

This is not a live read — no view tree, no object, no injection. It is not
signature *validation* for security (it reports the signing facts, it does not
adjudicate trust). And it does not modify anything — read-only, like every v1 verb.
