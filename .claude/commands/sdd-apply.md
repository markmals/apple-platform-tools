---
description: Regenerate a spec's implementation and tests on a target platform.
argument-hint: <spec-id> <platform>
---

# /sdd-apply $ARGUMENTS

You are applying a single spec to a single platform. Spec ID and target platform are: `$ARGUMENTS`.

Argument format: `<spec-id> <platform>` where `<platform>` is one of your project's platforms (`web`, `website`, `ios`, `android`, `windows`, `linux`, `cli`, `tui`, or `convex` — whichever survived `/setup`).

## Intent

Bring a single platform's implementation and tests **into conformance** with a single spec. The spec is authoritative; you are not editing the spec, you are aligning code to it. If the spec is wrong, stop and tell the user — they should edit the spec first, then re-invoke this command.

## Steps

1. **Locate the spec.** Search for the file whose frontmatter `id:` matches the spec ID. Read it in full, plus everything in its `depends-on` list.
2. **Identify existing reverse pointers.** `rg "SPEC: <spec-id>"` in the target platform's directory (`apps/<platform>/` or `services/convex/`). List the files that already point to this spec.
3. **Read the web reference implementation if the target is iOS or Android.** The web realization is the canonical worked example. Find it via the same `rg "SPEC: <spec-id>"` in `apps/web/`.
4. **Read the platform's CLAUDE.md** for idioms, frameworks, and test conventions.
5. **Plan the changes.** What files need to be created or modified? What tests need to exist? Surface this plan to the user before making changes.
6. **Make changes.** Write tests first (tagged with the spec ID and the relevant scenario sub-IDs). Implement to pass. Verify with the platform's `mise run test`.
7. **Verify reverse pointers.** Every changed implementation file must carry `// SPEC: <spec-id>` (or `// SPEC: <spec-id> (deviates: <reason>)` if a deliberate divergence is justified).
8. **Commit at natural boundaries.** Once tests are green and reverse pointers are in place, commit. See `.claude/rules/commit-discipline.md` for message style and staging discipline.

## Commit boundaries

Per spec, the natural boundaries are:

- **Test commit:** the failing tests that pin the spec's scenarios. Subject: `test: add scenarios for <spec-id> on <platform>`.
- **Implementation commit:** the minimum code to make them pass, with the `// SPEC: <id>` reverse pointer. Subject: `feat: implement <spec-id> on <platform>` (or `fix:` / `refactor:` as appropriate).

If the test and impl are tightly bound and the diff is small, one combined commit is fine. If multiple specs were applied in one session, commit each independently — never bundle "implemented X and Y" into one commit.

## Notes for the implementer agent

- Do **not** invent or rename spec IDs; they are stable.
- Do **not** edit the spec from this command. If the spec needs changes, that's `/sdd-reconcile`.
- Platform divergences must be explicit: comment them with `(deviates: <reason>)`.
- If a `depends-on` spec is not yet implemented on the target platform, surface this and offer to apply it first.

## Implementation status

This command's plumbing (drift checks, automated diff proposal) is **not yet implemented**. Until then, follow the steps above manually.
