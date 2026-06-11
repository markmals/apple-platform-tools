# Shared Spec Rules

> **This file is `@included` from `CLAUDE.md` via `@.claude/rules/spec-conventions.md`.** Keep it short — it loads on every session.

## The compact

- **Specs in `specs/` and `features/<n>/` are the source of truth.** The implementation must satisfy them.
- **Reverse pointers are mandatory.** Every class, function, or module that realizes a spec carries `// SPEC: <id>`. Tests are tagged with the spec IDs they verify.
- **Use `// SPEC: <id> (deviates: <reason>)`** when the implementation must differ from the spec. Use `// SPEC: manual` for genuinely incidental code with no behavioral contract.
- **The spec defines what; the test proves it; the implementation satisfies it.** None is the source of truth alone.
- **flexscope is single-platform (macOS).** There is no reference-vs-other-platform split — the discipline here is vertical (spec → test → impl), not lateral.

## Before writing implementation code

1. Read the spec file. Confirm the ID, depends-on chain, and behavior.
2. Read the existing patterns for similar specs (look for other `// SPEC:` annotations in the same area).
3. Write the failing tests first, tagged with the spec ID and scenario sub-IDs (Swift Testing; the `SampleAppKit` oracle for injection-dependent behavior).
4. Implement the minimum to pass the tests.
5. Verify with `/sdd-verify`.

## Before changing a spec

1. Search for the ID: `rg 'SPEC: <id>'`.
2. List the affected files and tests.
3. Update the spec.
4. Use `/sdd-apply <id>` to regenerate the implementation + tests — propose changes, do not auto-merge.

## Before changing implementation that has a spec

1. Decide: is this a bug fix the spec already requires, or a behavior change?
2. If behavior change: update the spec first, then run `/sdd-apply`.
3. If bug fix: just fix it and run `/sdd-verify`.

## Where to read more

- `specs/CONVENTIONS.md` — full conventions, kind taxonomy, frontmatter schema, drift rules.
- `specs/ARCHITECTURE.md` — components, the purity boundary, IPC contract, injection model, security model.
- `specs/STACK.md` — the toolchain catalog.
