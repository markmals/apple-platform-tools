---
description: Reconcile the spec and other platforms' implementations to match the source platform.
argument-hint: <source-platform>
---

# /sdd-reconcile $ARGUMENTS

You are reconciling: the source platform `$ARGUMENTS` (one of `web`, `website`, `ios`, `android`, `windows`, `linux`, `cli`, `tui`, `convex`) is treated as the **temporary source of truth**, and the spec + the other platforms must come into alignment with it.

## When to use this

Use this when a single platform's implementation has been edited directly (a fix, a new behavior, a refactor that changes externals) and the spec — and therefore the other platforms — are now stale. This is the inverse of `/sdd-apply`: instead of applying the spec to a platform, you are applying a platform to the spec.

This is **not for fixing bugs that were already in the spec**. Just edit the impl in that case. Reconcile when the _behavior_ changed, not when the implementation was made correct.

## Steps

1. **Determine which spec IDs were touched.** `rg "SPEC: " apps/<source-platform>/` filtered by recently-modified files (`git diff` against the last reconciled state).
2. **For each affected spec ID:**
   a. Read the source platform's current implementation and tests.
   b. Read the spec.
   c. Identify the behavioral diff: state, actions, transitions, observable outcomes.
   d. Propose a spec update (markdown diff). **Surface this to the user for review.**
   e. After the user approves the spec update, run `/sdd-apply <spec-id> <other-platform>` for each other platform that implements this spec.
3. **Do not auto-merge.** Every spec change and every cross-platform impl change is reviewed by the user.

## What gets reconciled

- Spec content (the markdown).
- Test files on the other platforms (they get regenerated to match the new spec).
- Implementation on the other platforms.

## What does NOT get reconciled

- The source platform's implementation (it's the input, not the output).
- Spec IDs (always stable).
- Architecture or design system documents (those need a deliberate edit, not reconciliation).

## Commit boundaries

Reconciliation produces several independent commits. Land them in order:

1. **Spec update** — after the user approves the markdown diff. Subject: `spec: reconcile <spec-id> with <source-platform> behavior`. Body explains what the source platform now does that the spec didn't capture.
2. **Per-platform realignment** — one commit per other platform that gets regenerated via `/sdd-apply`. Subject: `feat: align <platform> <spec-id> impl with reconciled spec` (or `refactor:` / `fix:` as appropriate).

Never bundle the spec edit with an implementation change — the spec change must be reviewable in isolation. See `.claude/rules/commit-discipline.md`.

## Implementation status

Manual until tooling lands. The agent can drive each step with the existing read/edit tools and `git diff`.
