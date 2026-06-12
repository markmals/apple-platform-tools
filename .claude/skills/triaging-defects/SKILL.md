---
name: triaging-defects
description: Use to work through entries in the root DEFECTS.md. Picks one entry, classifies it as fix-in-place / promote-to-spec / won't-fix-by-design, executes the resolution, and deletes the entry. The discipline that keeps DEFECTS.md from becoming a TODO graveyard.
---

# Triaging Defects

Work through entries in the root `DEFECTS.md` one at a time. For each entry, classify, resolve, and delete. The file should want to be empty by the time you stop.

The point of this skill is the drain. Without disciplined triage, `DEFECTS.md` becomes a TODO graveyard — a pile that grows faster than it shrinks, signalling "we have problems" without ever resolving them. Triage is what keeps the convention honest.

## When to use

- The root `DEFECTS.md` is non-empty and you're in a polish or fix pass on one of the tools.
- The user explicitly asks to triage defects, drain the file, or work through `DEFECTS.md`.
- A non-empty defect file has been sitting for long enough that the entries are stale — better to triage now than let the file calcify.

**Do NOT use this skill for:**

- Filing a new entry — that's `/sdd-defect`. This skill empties the file; the slash command fills it.
- Behavioral drift — that's `/sdd-drift`. If the defect is "spec says X but the implementation does Y," it doesn't belong in `DEFECTS.md` in the first place; surface that to the user and reclassify.
- Spec gaps — that's `[NEEDS CLARIFICATION]` during authoring or a spec amendment afterward. If you're triaging and realize the entry is actually a spec gap, that's the `promote-to-spec` path below.

## The classifier — three buckets

For each entry, classify into exactly one of:

### 1. Fix in place

The defect is genuinely sub-spec: cosmetic, polish, a tool-local quirk. The implementation could be fixed without changing any behavioral contract; the spec deliberately doesn't speak to it.

Resolution:

1. Reproduce.
2. Fix locally in the relevant tool's `Sources/<tool>/`.
3. Verify the fix using the `verification-before-completion` skill.
4. Delete the entry and any orphaned screenshot under the root `.defects/`.
5. Commit per `.claude/rules/commit-discipline.md` — `<scope>: <short description>`. The commit message body briefly notes the defect that prompted the fix; that's the durable record.

### 2. Promote to spec

While reproducing, you realize the spec actually _should_ speak to this. There's a missing scenario, an unspecified state, an unhandled error, a behavioral contract the spec should own.

Stop the fix. The "fix in place" path is wrong here, because the implementation would be wrong without this behavior no matter how it's written; that's a spec change, not a tool-local defect.

Resolution:

1. Identify the spec(s) that should grow to cover the case: a missing scenario in the relevant `story.*`, a new `error.*` entry, a new clause in the relevant `command.*` or `domain.*`, etc.
2. Draft the amendment. Add Gherkin scenarios with stable sub-IDs per `Specs/CONVENTIONS.md`.
3. Surface to the user for approval before the spec edit lands — promotion is a deliberate act.
4. Once approved, commit the spec change (`<spec-id>: ...`).
5. Run `/sdd-apply <spec-id>` to land the fix, mediated by the spec.
6. Delete the original `DEFECTS.md` entry — the spec change plus the implementation commit are the record.

### 3. Won't fix by design

The defect is real but acceptable. A tool idiom the spec deliberately leaves alone, a known limitation, a trade-off the user is comfortable with.

Resolution:

1. State the rationale clearly: why is this acceptable?
2. Delete the entry.
3. Note the rationale _briefly_ in the deletion commit message — one sentence under `<scope>: drop <title> from defects`.
4. Do **not** add a "won't fix" section to `DEFECTS.md`. The commit is the record. Re-adding the entry later (if it turns out to matter) is cheaper than letting the file grow a graveyard column.

If you find yourself classifying the same kind of defect as "won't fix" repeatedly, that's a signal — the relevant spec should explicitly acknowledge the trade-off. Surface that pattern to the user.

## Process per entry

1. **Read the entry.** Read it fully. If repro steps are unclear, ask the user — don't guess at intent.
2. **Reproduce.** For non-trivial defects, invoke `systematic-debugging` and follow the four-phase discipline. Reproduce against the tool-appropriate oracle — checked-in fixtures or an embedded corpus for the pure tools, or uitool's `SampleAppKit` (or a live target) for injection-dependent behavior — and observe the behavior firsthand (see `macos-development` → Verifying).
3. **Classify.** State the bucket and the reasoning before acting. Apply the promotion test (below) explicitly — don't classify "fix in place" by default just because that's the fastest path.
4. **Execute** the resolution for that bucket.
5. **Delete** the entry from `DEFECTS.md`. Also delete any screenshot under `.defects/` that the entry referenced — orphaned screenshots are noise.
6. **Commit** per `.claude/rules/commit-discipline.md`. One defect, one fix, one commit. Don't bundle multiple unrelated entries into one commit just because they came from the same file.

## The promotion test

Before classifying as "fix in place," explicitly ask:

> Could the implementation be rewritten differently and still be correct?

If yes — the spec is silent and the tool's idiom can produce a different correct shape — fix in place is right.

If no — any correct implementation must avoid this behavior — it belongs in the spec, not in `DEFECTS.md`. This is the same test `Specs/CONVENTIONS.md` uses to decide what is and isn't a spec.

This test is the most important step in the skill. Skipping it produces a `DEFECTS.md` full of entries that are quietly behavioral contracts, and a spec that doesn't say so.

## The drain principle

Entries should leave `DEFECTS.md` faster than they enter. The file is a drain, not a tracker.

If you notice the file growing — more entries arriving than leaving across multiple sessions — surface the pattern to the user. Two possibilities:

- The agent (or user) isn't triaging regularly enough. Schedule a drain pass.
- What's landing in the file should be specs instead. Bucket-by-bucket, are you mostly promoting? That's a sign the spec is under-specified for this domain and the intake category is wrong.

Either way, name the pattern. Don't quietly accept growth.

## Screenshots and `.defects/`

Defect entries can reference screenshots under the root `.defects/`. These are committed to the repo (not gitignored) so:

- They survive across machines and sessions.
- They show up in PRs and reviews when an entry lands.
- They're self-contained: a fresh checkout has both the entry and the picture.

The trade-off is that screenshots add bytes to the repo. They're typically small (a few hundred KB at most), and the triage discipline deletes them with their entries — so the directory should stay small. If the `.defects/` directory is bloating, that's another signal the file isn't draining.

When you delete an entry, also delete any screenshot path it referenced. Run `ls .defects/` after triage to check for orphans.

## Red flags — stop and reclassify

| Symptom                                                                          | What it means                                                                                                                                  |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| You're about to write a test tagged with a spec ID to cover the defect           | It's a spec change. Promote.                                                                                                                   |
| The fix changes behavior a spec ID already names                                 | It's a spec change. Promote.                                                                                                                   |
| You're tempted to add a `// SPEC: manual` annotation to justify the fix          | Allowed, but double-check the code is genuinely incidental. If any correct implementation would need an analogous fix, it's a spec.           |
| The entry has been sitting in `DEFECTS.md` across multiple sessions              | Triage it now or promote it. Don't leave it.                                                                                                   |
| You're tempted to mark the entry "deferred" or "needs investigation" and move on | That's `DEFECTS.md` becoming a tracker. Delete or commit to a bucket.                                                                          |
| Multiple entries describe variations of the same underlying issue                | One root cause. Either fix once and delete all entries, or promote once and delete all entries.                                                |

## Anti-patterns

- **"Closed" markers.** Don't accumulate fixed entries with a "closed" annotation. Delete them. The commit is the record.
- **Severity, priority, assignee.** Don't add these fields. If you find yourself wanting them, you're rebuilding Jira.
- **Batched fixes.** Don't bundle unrelated entries into one commit just because they share `DEFECTS.md`. One defect, one fix, one commit — per `.claude/rules/commit-discipline.md`.
- **Speculative entries.** If you can't reproduce, you can't classify. Ask the user for clearer repro before triaging.
- **Skipping the promotion test.** "Just fix it locally" is the wrong default. The test is short; run it.

## Related skills

- `systematic-debugging` — the four-phase discipline for reproducing and root-causing each entry before classifying.
- `brainstorming-feature` — for the promote-to-spec path when the amendment is large enough that it warrants spec-style exploration (new story, new flow). Smaller amendments (a scenario, an error entry) can be edited directly.
- `verification-before-completion` — the gate before claiming an entry is fixed. Run the verifying command; read its output; only then delete the entry.
- `macos-development` (→ Verifying) — reproducing uitool runtime defects against the `SampleAppKit` oracle or a live target.
- `implementing-a-spec` — the workflow that `/sdd-apply` uses to land a promoted spec change.
