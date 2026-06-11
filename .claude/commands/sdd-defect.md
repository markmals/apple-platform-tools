---
description: File a sub-spec defect observation into the root DEFECTS.md without breaking flow.
argument-hint: <short description>
---

# /sdd-defect $ARGUMENTS

You are filing a sub-spec defect observation. `$ARGUMENTS` is a free-text description of what was observed.

## Intent

Capture an observation while it's fresh, in the structured shape from `.claude/templates/DEFECTS.md`, then return control to the user so they don't lose their current train of thought. This is the **intake** command. Resolution happens later via the `triaging-defects` skill — not now.

Sub-spec defects are observed cosmetic / polish / quirk issues that the spec deliberately doesn't cover. See `Specs/CONVENTIONS.md` → "What is NOT a spec" for the boundary.

## Steps

1. **Resolve the target file.** There is one defects ledger for the whole package: the root `DEFECTS.md`. If it doesn't exist yet, copy `.claude/templates/DEFECTS.md` to `DEFECTS.md` at the repo root.
2. **Gather the entry fields.** Use `AskUserQuestion` only when the slash command argument didn't already supply the answer. The fields are:
    - **title** — short imperative (e.g. "redump emits trailing comma on empty load-command list")
    - **where** — file path, tool, or command
    - **symptom** — one sentence: what the user sees
    - **repro** — minimal steps to reproduce

    Do **not** ask for severity, priority, owner, or status — they don't exist in this system. If the user's argument already contains enough detail to infer a field, infer it; don't re-ask.

3. **Offer a screenshot, but don't insist.** If the defect is visual, ask once whether to capture one. If yes, capture it, save the file to `.defects/<slug>.png` (slug derived from the title), and reference the path from the entry. If the user declines or is mid-flow, skip — they invoked this command to capture quickly, not to context-switch.
4. **Append the entry under `## Open`.** Use this shape exactly (omit screenshot/notes lines if empty):

    ```markdown
    ### <title>

    - observed: <YYYY-MM-DD>
    - where: <where>
    - symptom: <symptom>
    - repro: <repro>
    - screenshot: <optional path>
    - notes: <optional>
    ```

    If the file still contains the `_(empty)_` placeholder under `## Open`, replace it with the new entry. Otherwise append after the last existing entry.

5. **Confirm in one line and stop.** Output a single short line:

    ```
    Filed: <title> in DEFECTS.md
    ```

    Do **not** start triaging. Do **not** offer to fix. Do **not** open the relevant code. The user invoked this command to capture without derailing; respect that.

## Constraints

- **Don't propose fixes.** Triage is a separate, deliberate act — the `triaging-defects` skill handles it.
- **Don't invoke `systematic-debugging`.** Filing is not investigating.
- **Don't open the implementation file** referenced by `where`. The point is capture, not exploration.
- **One entry per invocation.** If the user describes multiple defects, file the first and tell them to re-invoke for the others. Bundling defeats the structured-intake purpose.

## Commit

Filing a defect is a small, durable change that should land in git immediately — the entry is the contract until triaged, and leaving it in the working tree across other work risks it getting bundled into an unrelated commit.

Commit as soon as the entry is appended:

```
treewide: file defect <title>
```

If a screenshot was captured, include it in the same commit. Stage explicitly by path — never `git add .` — per `.claude/rules/commit-discipline.md`.

## Implementation status

The slash command is scaffolded; the agent fulfills it manually using `Edit`, `Write`, `AskUserQuestion`, and (optionally) a screenshot capture. No additional tooling required.
