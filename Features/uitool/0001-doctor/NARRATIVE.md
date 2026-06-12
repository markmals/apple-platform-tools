---
id: narrative.uitool.doctor
kind: narrative
---

# Preconditions & attachable apps

## Who this is for

A coding agent reverse-engineering a macOS app's runtime UI on behalf of the human researcher driving it — both want a fast, unambiguous answer to "can I inspect this app right now, and if not, what's wrong?" before anything risky happens.

## The situation today

Getting code into a hardened first-party app on Apple Silicon depends on a brittle stack of machine-wide settings — SIP lowered to Permissive Security, an AMFI boot-arg, a library-validation override, the arm64e preview ABI, and an arm64e-built dylib. When any one link is missing, the only symptom is a silent "dylib didn't load" with no clue which link broke. An agent faced with that has nothing to act on: it cannot tell a misconfigured machine from a wrong target from a genuinely un-attachable app, so it either gives up or guesses. There is also no quick way to ask "which running apps could I even attach to, and which are hardened?" without manual `ps`/`codesign` archaeology.

## What we're building

Two read-only commands the agent runs at the start of every session. The first reports a verdict on each precondition independently — pass or fail, and for each failure a single concrete remedy — so a half-configured machine produces a clean, itemized failure instead of a mystery. The second lists the processes that are candidates for attachment, each annotated with whether it is hardened and which architecture it runs, so the agent can pick a reachable target and set its expectations. Both only read the local machine and the process list; neither touches a target process.

## Why this matters

The agent gets a clean, machine-readable failure it can act on — or a clear green light — instead of a confusing injection error after the fact. That turns the hardest, most failure-prone part of the tool into the safest and most legible first step.

## What this is NOT

Not injection, attachment, or any query against a target's view tree — those are later commands. A fixer only on request: this feature detects and instructs by default, and changes boot-args / library validation only under the explicit, opt-in `--fix` flag — which echoes every command, never runs implicitly, and stops at the SIP/reboot steps it cannot complete. It never mutates boot security implicitly ([[domain.uitool.injection]]).
