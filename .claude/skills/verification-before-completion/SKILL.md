---
name: verification-before-completion
description: Use before claiming any work is complete, fixed, or passing. Requires running the verifying command in this turn and reading its output before stating success. Evidence before assertions, always.
---

# Verification Before Completion

Claiming work is complete without verification is dishonesty, not efficiency. Evidence before claims, always.

**Lifted from superpowers' verification-before-completion skill.** Slimmed; the discipline is unchanged.

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command **in this turn**, you cannot claim the result.

## The gate

Before stating success, satisfaction, or completion:

```
1. IDENTIFY  — what command proves the claim?
2. RUN       — execute the full command, fresh, no shortcuts
3. READ      — full output, exit code, failure count
4. VERIFY    — does the output confirm the claim?
                - No  → state actual status with evidence
                - Yes → state claim with evidence
5. CLAIM     — only now
```

Skip any step = lying.

## What proves what

| Claim                 | Required evidence                             | Insufficient                                   |
| --------------------- | --------------------------------------------- | ---------------------------------------------- |
| Tests pass            | Test command output: 0 failures, this turn    | "Last run was clean", "Should pass now"        |
| Linter clean          | Linter output: 0 errors, this turn            | Partial check, extrapolation from related code |
| Build succeeds        | Build command exit 0, this turn               | Linter passed, types passed                    |
| Bug fixed             | Failing reproduction now passes               | Code changed, "I think it's fixed"             |
| Regression test works | Red-green cycle verified                      | Test passes once on the fixed code             |
| Subagent finished     | `git status` / `git diff` shows the changes   | Subagent's own success report                  |
| Spec implemented      | `/sdd-verify` passes for the relevant spec ID | Code looks right                               |
| All requirements met  | Line-by-line spec checklist                   | Tests pass                                     |

For a regression test, the full red-green proof:

```
1. Write the test
2. Run it (with fix) — must PASS
3. Revert the fix
4. Run it — must FAIL (otherwise the test isn't testing what you think)
5. Restore the fix
6. Run it — must PASS again
```

Without step 4, you don't know the test catches the bug.

## Red flags — stop

- Using "should", "probably", "seems to", "I'm pretty sure"
- "Great!", "Perfect!", "Done!" before running anything
- About to commit / open a PR without re-running tests
- Trusting a subagent's success report without checking the diff
- Claiming success based on a partial check ("typecheck passed, build will pass")
- Tired and wanting the work to be over
- "Just this once"

Any of these = run the verification first.

## Common rationalizations

| Excuse                    | Reality                                           |
| ------------------------- | ------------------------------------------------- |
| "Should work now"         | Run the command.                                  |
| "I'm confident"           | Confidence ≠ evidence.                            |
| "Linter passed"           | Linter doesn't compile. Linter doesn't run tests. |
| "Subagent said success"   | Verify independently — check the diff.            |
| "I'm tired"               | Not an excuse.                                    |
| "Partial check is enough" | Partial proves nothing.                           |

## How to phrase results

After running the verification:

```
✅ I ran `mise run -C apps/web test` — 47/47 tests pass. Implementation complete.
```

Not:

```
❌ "Looks good now!"
❌ "Tests should be passing."
❌ "I think we're done."
```

Even when the result is bad, state it cleanly:

```
mise run -C apps/web test reports 2 failures:
  - vm.items.list / [scenario.items.list.populated] — expected 3 items, got 2
  - vm.items.create / [scenario.item.create.duplicate-email] — no error thrown
Investigating now.
```

## When to apply

**Always before:**

- Saying "done", "complete", "fixed", "passing", "ready", "shipped"
- Saying anything positive about the state of the work
- Committing (or asking the user to commit)
- Moving to the next task in TodoWrite
- Reporting subagent success up to the user
- Closing a /sdd-apply session

The rule applies to exact phrases, paraphrases, synonyms, and **anything that implies success**.

## Why this matters

The cost of a false-positive completion claim is:

- The user reviews work that isn't done
- Subsequent work is built on a broken foundation
- Trust erodes; the user starts double-checking everything
- You waste your own time when the issue surfaces later

Running the verification command takes seconds. Skipping it can cost hours.

## Bottom line

Run the command. Read the output. Then claim the result. Non-negotiable.
