---
description: Scan a feature or spec for [NEEDS CLARIFICATION] markers and resolve them with the user.
argument-hint: <feature-id-or-slug-or-spec-id>
---

# /sdd-clarify $ARGUMENTS

You are clarifying unspecified details in: `$ARGUMENTS`.

Argument forms:

- A feature slug: `0001-managing-items` (clarify everything in `features/<slug>/`)
- A feature ID: `0001` (resolve to the slug; same as above)
- A spec ID: `story.item.create` (clarify just that one spec file)

## Intent

Find every `[NEEDS CLARIFICATION: <question>]` marker in the targeted spec(s), prioritize the questions, surface the most important ones to the user, then edit the answers back into the file(s) — replacing the marker with the resolved content.

Inspired by spec-kit's `/speckit.clarify`. The convention is documented in `specs/CONVENTIONS.md` → "Marking unspecified or ambiguous content".

## Steps

1. **Locate the target.** Resolve the argument:
    - Feature slug or numeric ID → the directory `features/<NNNN>-<slug>/`.
    - Spec ID → the file under that directory (or `specs/`) whose frontmatter `id:` matches.
2. **Find markers.** `rg -n '\[NEEDS CLARIFICATION:' <target>` to enumerate every marker with file + line.
3. **Categorize and prioritize.** Group markers by spec kind and category:
    - **Functional / behavioral** (what the user does or sees) — usually highest priority
    - **Domain / data** (entity shapes, identity, invariants)
    - **Interaction / UX** (flow specifics, error/empty states)
    - **Non-functional** (performance, retention, auth, compliance)
    - **Integration** (external services, formats)
4. **Present up to 5 questions to the user, one at a time.** For each:
    - Quote the marker and its surrounding context (the sentence/scenario/field it lives in).
    - Restate the question clearly.
    - Offer 2-4 multiple-choice options when the answer space is small; otherwise ask open-ended.
    - Use `AskUserQuestion` for clean structured replies.
5. **Apply the answer.** Edit the spec file: replace the `[NEEDS CLARIFICATION: ...]` token with the resolved content. Keep wording compatible with the surrounding sentence. Preserve line breaks and surrounding markdown.
6. **Verify.** After all questions are resolved, re-run `rg '\[NEEDS CLARIFICATION:'` over the target. Report any remaining markers (lower-priority ones not addressed in this pass) so the user knows what's left.

## Constraints

- **Edit only the target spec(s).** Do not modify code, tests, or unrelated files.
- **One question per AskUserQuestion turn.** Don't batch — context matters per question.
- **Don't invent answers.** If the user response is ambiguous, ask a follow-up rather than guessing again.
- **Stop at 5.** If more than 5 high-priority markers remain, finish the first 5 and tell the user to re-invoke.

## Output

When done, summarize:

- N markers resolved (with file + line + one-line resolution)
- M markers deferred (with file + line + reason)
- Suggested next action (typically `/sdd-analyze <feature>` or proceeding to implementation)

## Commit

After resolving the markers, commit the edits. See `.claude/rules/commit-discipline.md` for style.

Natural boundaries:

- **One commit per coherent topic of clarifications.** If five markers in one feature all clarify duplicate-email handling, that's one commit (`spec: clarify duplicate-email handling in <feature>`). If they clarify unrelated concerns, split.
- **Spec edits only.** This command does not touch code or tests, so the commit should contain only files under `features/` or `specs/`. If your working tree has unrelated changes, stage explicitly — do not `git add .`.

## Implementation status

The slash command is scaffolded; the agent drives the steps manually using `rg`, `AskUserQuestion`, and `Edit`. No additional tooling is needed.
