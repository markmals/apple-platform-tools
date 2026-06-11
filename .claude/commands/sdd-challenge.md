---
description: Adversarially review a spec's implementation on a platform — try to break it.
argument-hint: <spec-id> <platform>
---

# /sdd-challenge $ARGUMENTS

You are running a standalone adversarial review of one spec on one platform: `$ARGUMENTS`.

Argument format: `<spec-id> <platform>` where `<platform>` is one of your project's platforms (`web`, `website`, `ios`, `android`, `windows`, `linux`, `cli`, `tui`, or `convex` — whichever survived `/setup`).

## Intent

Subject an **already-implemented** spec to the refutational pass on its own, outside the `implementing-a-spec` flow — when you distrust existing code, inherited a feature, or want a second, hostile opinion before shipping.

This is the same third stage `implementing-a-spec` runs, invoked directly. It uses the `adversarial-review` skill.

**Read-only.** This command reports defects; it does not fix them. Remediation routes back through the normal flow (`systematic-debugging` for root cause → `test-driven-development` → `/sdd-apply`). Surfacing is the deliverable.

## Steps

1. **Locate and read the spec.** Find the file whose frontmatter `id:` matches the spec ID. Read it in full, plus its `depends-on` chain — you need the invariants and every Gherkin scenario to judge fidelity.
2. **Locate the implementation and tests.** `rg "SPEC: <spec-id>"` in the target platform's directory (`apps/<platform>/` or `services/convex/`). Record the implementing files; find the tests tagged with the spec ID and its scenario sub-IDs.
    - **No reverse pointer found?** The spec isn't implemented on this platform. Report `INSUFFICIENT DATA — <spec-id> has no implementation on <platform>` and stop. There is nothing to refute.
3. **Confirm the suite is green first.** Run the platform's tests for this spec (`mise run -C apps/<platform> test`, filtered to the spec ID where the runner allows). If tests are **red**, stop and report it — a failing suite is a different problem; route it to `systematic-debugging`, not to the adversary. The refutational pass assumes code that already passes its own checks, exactly as the third stage runs only after the two confirmatory reviews are ✅.
4. **Dispatch the adversary.** Spawn a fresh subagent on a **different model** from whatever built the code — default `model: "opus"` — that never saw the implementation written. Tell it to read `.claude/skills/adversarial-review/SKILL.md` and apply it. Paste in: the full spec text, the implementing files, and the test files. Do not say "go read them" — curate the context.
5. **Relay the verdict** in the skill's output format (below). Verify the adversary's claimed defects carry a concrete reproduction; drop any finding it couldn't actually trace (the skill forbids fabricated flaws — hold it to that).
6. **Act on the verdict:**
    - **BROKEN** → surface the defects. Do **not** auto-fix. Offer to remediate through the normal flow.
    - **SPEC GAPS** → surface to the user; route to a spec edit (`/sdd-reconcile` or a deliberate spec change), never a silent code change.
    - **CONVERGED** → report clean. The adversary tried all five lenses and found nothing real.

## Output format

```
ADVERSARIAL REVIEW — <spec-id> on <platform>
Intent: <one-line summary from the spec>
Suite: GREEN (n tests)

DEFECTS (must fix):
  1. <location> — <what's wrong> — repro: <exact input/action> — got <X>, spec requires <Y>
  ...

SUSPICIONS (unverified):
  - <observation and the input that might trigger it>

SPEC GAPS (route to spec):
  - <implemented behavior no clause covers, or clause the code reinterpreted>

VERDICT: BROKEN (n defects) | CONVERGED
```

## Notes

- **Read-only.** This command never edits implementation or spec files. It audits.
- **Different model is the point.** Cognitive diversity against the code's author catches shared blind spots; reusing the implementer's model defeats the stage.
- **Precondition: green tests.** Refuting red code spends the adversary on the wrong layer.
- **No fabricated flaws.** Every reported defect carries a traced reproduction; suspicions stay labelled as suspicions.

## Implementation status

Manual and agent-driven, like the other `sdd-*` commands. `rg` to locate the reverse pointers, the platform test runner to confirm green, and a dispatched subagent to run the `adversarial-review` skill. No aggregation tooling yet.
