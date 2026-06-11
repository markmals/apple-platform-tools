---
name: implementing-a-spec
description: Use when implementing a spec on a target platform — `/sdd-apply <id> <platform>`. Dispatches a fresh subagent per spec, runs spec-compliance review, code-quality review, then an adversarial refutational pass, and updates TodoWrite as it goes. This is the default "how to write code" workflow for this repo.
---

# Implementing a Spec

Each spec ID is a unit of work. To implement one on a target platform, you dispatch a fresh subagent that writes failing tests, makes them pass, attaches a `// SPEC: <id>` reverse pointer, then submits for review: spec compliance, code quality, then an adversarial pass that assumes the code is broken and tries to break it (the `adversarial-review` skill).

Lifts patterns from superpowers' subagent-driven-development. Adapted to our spec layer, our reverse-pointer convention, and the fact that we don't use feature branches.

**Default workspace:** the user's current branch (typically `main`). Do not prompt for worktree vs. branch — assume the user is on whatever is checked out.

## When to use

- The user invoked `/sdd-apply <spec-id> <platform>`.
- The user said "implement <spec-id> on <platform>".
- You are about to write substantive new code that realizes a spec.

**Do NOT use this skill for:**

- Trivial edits (renaming a constant, fixing a typo, adding a single test): do those inline. A failed trivial dispatch costs more than just doing it yourself.
- Bug fixes: use `systematic-debugging` first to find the root cause, then this skill to apply the fix.
- Spec authoring: use `brainstorming-feature` instead.

## Core principle

**Fresh subagent per spec + layered review (confirm, then refute) = high quality, fast iteration.**

The controller (you) does:

- Read the spec(s) and any cross-platform reference implementation
- Curate the exact context the implementer subagent needs
- Manage TodoWrite state
- Dispatch and review subagents

The implementer subagent does:

- Write failing tests tagged with the spec ID
- Implement the minimum to pass
- Attach the reverse pointer
- Self-review

The reviewer subagent(s) do:

- Spec compliance: does the code satisfy the spec? Are reverse pointers correct?
- Code quality: is the code idiomatic, well-named, free of duplication?
- Adversarial: assume it's broken and try to break it — un-enumerated edges, aliasing/mutation/concurrency/resource bugs, tests that would pass even if the behavior were wrong. See the `adversarial-review` skill.

## Process

```
For each spec ID:
  1. Read spec + depends-on chain + web reference impl (if target ≠ web)
  2. Identify existing reverse pointers, tests, and gaps on the target platform
  3. Construct full context for the implementer (don't make them re-read)
  4. Dispatch implementer subagent
     - Subagent asks questions? Answer, re-dispatch.
     - Subagent reports DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED.
  5. Dispatch spec-compliance reviewer
     - Reviewer finds gaps? Implementer fixes, re-review.
     - Reviewer ✅? Continue.
  6. Dispatch code-quality reviewer
     - Reviewer finds issues? Implementer fixes, re-review.
     - Reviewer ✅? Continue.
  7. Dispatch adversarial reviewer (adversarial-review skill — fresh context, different model)
     - VERDICT: BROKEN? Implementer fixes each defect; re-run from step 5.
     - VERDICT: CONVERGED? Mark task complete in TodoWrite.
  8. Move to next spec.

When all specs done:
  9. Run /sdd-verify <platform> to confirm tests pass.
  10. Commit at the natural boundary (see "Commit" below), then surface results to user.
```

## Step-by-step

### 1. Read everything you need before dispatching

- The spec file. Read it in full.
- Every spec in its `depends-on` chain. Skim, but read the field names and invariants.
- If target is iOS or Android, find the web reference implementation: `rg "SPEC: <spec-id>" apps/web/`. Read it as a worked example.
- The platform's `apps/<platform>/CLAUDE.md` for idioms and test conventions.
- Existing patterns near where the new code will live (look for other `// SPEC:` annotations in the same area).

The implementer should not need to read any of this — you're providing the curated context.

### 2. Build TodoWrite for the session

If implementing multiple specs in one session, create a TodoWrite item per spec. Mark each `in_progress` only when you're actively dispatching for it. Mark `completed` only after both reviews pass.

### 3. Dispatch the implementer subagent

Use `subagent_type: "general-purpose"` and `model: "sonnet"`. Provide:

- The full spec text (don't say "read specs/foo/bar.md", paste the contents).
- The full text of every depends-on spec, in the order you want it considered.
- The full web reference implementation file(s) if target is iOS or Android.
- The relevant section of `apps/<platform>/CLAUDE.md` (idioms, test framework setup).
- Explicit instructions:
    1. **Write failing tests first**, tagged with the spec ID and the relevant `[scenario.<id>]` prefixes per `apps/<platform>/CLAUDE.md`.
    2. Run the tests to **confirm they fail** for the right reason.
    3. Implement the **minimum code** to make the tests pass.
    4. **Attach `// SPEC: <id>`** to the implementing class/function/module.
    5. **Self-review**: re-read the spec and the implementation; fix gaps inline.
    6. Report status: `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`. If `BLOCKED`, explain.

Tell the implementer **not to commit**. The implementer works in a partial state during dispatch; the controller commits once both reviews pass (see "Commit" below).

### 4. Handle implementer status

- **DONE** → continue to spec-compliance review.
- **DONE_WITH_CONCERNS** → read the concerns. If correctness or scope, address before review. If observations, note and proceed.
- **NEEDS_CONTEXT** → provide the missing context, re-dispatch. Don't tell them to "go look it up" — paste it.
- **BLOCKED** → assess:
    - Context problem? Provide more context, same model.
    - Reasoning shortfall? Re-dispatch with `model: "opus"`.
    - Task too large? Split it; revise TodoWrite.
    - Plan/spec wrong? Stop and surface to the user.

Never silently retry the same dispatch.

### 5. Dispatch the spec-compliance reviewer

Use `subagent_type: "general-purpose"` and `model: "sonnet"`. Provide:

- The full spec text (same as before).
- The list of files the implementer touched (get from `git status` / `git diff`).
- The contents of those files (paste).

Instructions:

1. Confirm the implementation **satisfies every clause of the spec**.
2. Confirm the **reverse pointer** `// SPEC: <id>` is present on the implementing unit.
3. Confirm there are tests covering **every Gherkin scenario** in the spec, with the right `[scenario.<id>]` prefixes.
4. Confirm there is **nothing extra** that the spec didn't require (no scope creep).
5. Output: ✅ Approved, OR ❌ list of specific gaps and overreach.

If gaps: the same implementer subagent fixes them; re-dispatch the reviewer until ✅. Do not skip the re-review.

### 6. Dispatch the code-quality reviewer

Same model, same general approach. Provide the same files plus the platform CLAUDE.md idioms section.

Instructions:

1. Check **idioms**: does it look like idiomatic UIKit / Compose / TanStack Start code?
2. Check **naming**: names match the spec's vocabulary; no synonyms drift.
3. Check **duplication**: no repeated logic that should be extracted.
4. Check **size**: any file growing too large?
5. Check **error handling**: only at boundaries; no defensive hand-wringing in internal code.
6. Output: ✅ Approved, OR ❌ list of issues categorized as Important / Nice-to-have.

**Signal-to-noise gate — apply before reporting.** A long review buries its real findings. Drop anything that is: a style nit the formatter or linter already owns, a restatement of what the code does, context inflation with no concrete cost, or a fix that only helps this one site. For each surviving finding, apply the **generalization test** — name three other places the same issue would bite. If you can't, it's a nitpick, not an Important issue. A short list of real issues beats a long list that hides them.

Implementer fixes Important issues. Nice-to-have is the user's call.

### 7. Dispatch the adversarial reviewer

The code now satisfies the spec and reads cleanly. That is exactly when confirmatory review stops looking and real defects hide. Run the `adversarial-review` skill as the final stage.

- **Fresh context, different model.** Dispatch a new subagent that never saw the code get built. Default it to `model: "opus"` even though the earlier reviewers ran on `sonnet` — the cognitive diversity is the point. Tell it to read `.claude/skills/adversarial-review/SKILL.md` and apply it.
- Provide the full spec text and the files the implementer touched (paste them, don't say "go read").
- It returns the skill's output format: DEFECTS / SUSPICIONS / SPEC GAPS / VERDICT.

Handle the verdict:

- **BROKEN** → the implementer subagent fixes each defect. Re-run spec-compliance and code-quality if the fix was substantial, then re-run the adversary. Loop.
- **SUSPICIONS** → verify each before acting; drop the ones that don't reproduce. Never fix a suspicion blind.
- **SPEC GAPS** → surface to the user and route to the spec via a spec edit, not a silent implementer change.
- **CONVERGED** → the adversary is reduced to nitpicks or inventing problems. Done. Mark the task complete in TodoWrite.

Loop until VERDICT is CONVERGED.

### 8. Verify completion

After all spec implementations are done:

```sh
mise run -C apps/<platform> test
```

Use the `verification-before-completion` skill before claiming the work is complete.

## Constraints

- **Never dispatch parallel implementer subagents on the same files.** They'll conflict.
- **Never let the implementer commit.** It works mid-task; the controller commits at the natural boundary once reviews pass.
- **Never skip reviews.** All three stages — spec-compliance, code-quality, adversarial — are non-negotiable.
- **Never let the implementer self-review replace actual review.** All are needed.
- **Never start code-quality review before spec-compliance is ✅.** Wrong order.
- **Never run the adversarial pass before both confirmatory reviews are ✅.** Refuting code that doesn't match the spec yet spends the adversary on the wrong layer.

## Commit

Once both reviews pass and `/sdd-verify` is green, commit. See `.claude/rules/commit-discipline.md` for message style.

Natural boundaries per spec applied:

- **Test commit:** `test: add scenarios for <spec-id> on <platform>` — the failing tests that pin the spec.
- **Implementation commit:** `feat: implement <spec-id> on <platform>` — the minimum code that makes the tests pass, with the `// SPEC: <id>` reverse pointer attached.

Combine the pair into one commit if the diff is small and they're tightly bound. If you applied multiple specs in one session, commit each independently — never bundle "implement X and Y" into one commit.

Fixups from review (either spec-compliance or code-quality) belong in the same commit pair if not yet pushed; otherwise land them as a follow-up commit (`fix:` or `refactor:`).

## Model selection

- Default: `sonnet` for the implementer and both confirmatory reviewers.
- **Adversarial reviewer: `opus` by default** — cognitive diversity against the Sonnet-built code is the point of the stage. A different model family is better still when one is available.
- Escalate the implementer to `opus` only if the subagent reports `BLOCKED` due to reasoning, not context.
- Never `haiku` — it's been observed to improvise destructive recovery (e.g. `git reset --hard`) when confused.

## Skip dispatch entirely when

The change is so trivial that even Sonnet feels like overhead:

- Renaming a constant
- Fixing a one-line typo
- Adding a single missing test case to an existing test file
- Updating a comment

Just do it inline. A failed trivial dispatch is more expensive than the work.

## Related skills

- `brainstorming-feature` — produces the spec(s) this skill implements
- `test-driven-development` — the discipline subagents follow inside their dispatch
- `adversarial-review` — the third review stage; the refutational pass that runs after both confirmatory reviews
- `verification-before-completion` — the gate before claiming a spec is done
- `systematic-debugging` — when an implementer gets stuck on a confusing failure

## Slash commands that invoke this skill

- `/sdd-apply <spec-id> <platform>` — primary entry point
- `/sdd-reconcile <platform>` — uses this skill in reverse (apply a platform's behavior to the spec, then back to other platforms)
