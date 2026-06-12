---
description: Regenerate a spec's implementation and tests.
argument-hint: <spec-id>
---

# /sdd-apply $ARGUMENTS

You are applying a single spec to the package. The spec ID is: `$ARGUMENTS`.

Argument format: `<spec-id>` — a stable ID from a spec's frontmatter (e.g. `command.sdk-api.check`, `domain.agent-cli`, `story.headerdump.dump-framework`, `error.uitool.stale-node`). The ID names the tool or shared library it lives under; you don't pass a target separately.

## Intent

Bring the implementation and tests **into conformance** with a single spec. The spec is authoritative; you are not editing the spec, you are aligning code to it. If the spec is wrong, stop and tell the user — they should edit the spec first, then re-invoke this command.

## Steps

1. **Locate the spec.** Search for the file whose frontmatter `id:` matches the spec ID. Read it in full, plus everything in its `depends-on` list.
2. **Identify existing reverse pointers.** `rg "SPEC: <spec-id>" Sources/`. List the files that already point to this spec.
3. **Read the shared-library contract it builds on.** Most tools realize behavior through `AgentCLI` (the machine contract) and the other shared libraries (`MachOFoundation`, `RuntimeKit`, `SDKIndex`). Read the relevant ones so the implementation conforms to them, not a private reinvention.
4. **Read `macos-development`** for idioms, frameworks, and test conventions (Swift 6 + ArgumentParser + Swift Testing; ObjC/XCTest for RuntimeKit).
5. **Plan the changes.** What files need to be created or modified? What tests need to exist? Surface this plan to the user before making changes.
6. **Make changes.** Write tests first (tagged with the spec ID and the relevant scenario sub-IDs). Implement to pass. Verify with `mise run test` (or `swift test`, filtered by spec ID where useful).
7. **Verify reverse pointers.** Every changed implementation file must carry `// SPEC: <spec-id>` (or `// SPEC: <spec-id> (deviates: <reason>)` if a deliberate divergence is justified).
8. **Commit at natural boundaries.** Once tests are green and reverse pointers are in place, commit. See `.claude/rules/commit-discipline.md` for message style and staging discipline.

## Commit boundaries

Per spec, the natural boundaries are:

- **Test commit:** the failing tests that pin the spec's scenarios. Subject: `<spec-id>: add scenarios`.
- **Implementation commit:** the minimum code to make them pass, with the `// SPEC: <id>` reverse pointer. Subject: `<spec-id>: implement` (or a `fix`/`refactor`-flavored description as appropriate).

If the test and impl are tightly bound and the diff is small, one combined commit is fine. If multiple specs were applied in one session, commit each independently — never bundle "implemented X and Y" into one commit.

## Notes for the implementer agent

- Do **not** invent or rename spec IDs; they are stable.
- Do **not** edit the spec from this command. If the spec needs changes, that's a deliberate spec edit.
- Deliberate divergences must be explicit: comment them with `(deviates: <reason>)`.
- If a `depends-on` spec is not yet implemented, surface this and offer to apply it first.

## Implementation status

This command's plumbing (drift checks, automated diff proposal) is **not yet implemented**. Until then, follow the steps above manually.
