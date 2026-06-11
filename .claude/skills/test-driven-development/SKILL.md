---
name: test-driven-development
description: Use when writing any production code in this repo — features, bug fixes, refactors, behavior changes. Write the failing test first, watch it fail, write minimal code to pass, refactor green. Tagged with the spec ID and scenario sub-ID per the platform's test conventions.
---

# Test-Driven Development

Write the test first. Watch it fail. Write the minimal code to pass it. Refactor while green.

**Core principle:** if you didn't watch the test fail, you don't know if it tests the right thing.

**Lifted from superpowers' TDD skill.** Slimmed for this repo and adapted to our spec-tagging convention.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

If you wrote code before the test, **delete it** and start over. Don't keep it as "reference". Don't "adapt it" while writing the test. Delete means delete.

## When to use

**Always:**

- New features (every spec implementation)
- Bug fixes (write a failing regression test first)
- Behavior changes
- Refactors that change observable behavior

**Exceptions (ask first):**

- Generated code
- Configuration files
- Throwaway prototypes that will be deleted, not kept

If you're thinking "skip TDD just this once" — stop. That's rationalization.

## Red → Green → Refactor

```
1. RED      Write one failing test for one behavior.
2. Verify   Run the test. Confirm it fails — for the right reason.
3. GREEN    Write the minimal code to make it pass.
4. Verify   Run the test. Confirm it passes. Confirm other tests still pass.
5. Refactor Clean up while staying green.
6. Repeat   Next failing test for next behavior.
```

### RED — write one failing test

- One behavior per test.
- Clear name: `[scenario.<id>] <what the user observes>`.
- Test real code; mock only what you can't control (network, time, randomness).
- **Example or invariant?** A specific scenario ("creating with valid info shows it in the list") is an example test. A universally-quantified rule from a `domain.<entity>` spec — "name is never blank after trim", "for all valid items, encode/decode round-trips" — is a **property**, and the failing test you write first is a property test. See "Invariants get a property, not just examples" below. Don't settle for examples when the spec said "for all".

```ts
// Vitest, web
describe("vm.items.list", () => {
    it("[scenario.items.list.empty] shows empty state when no items exist", () => {
        const vm = createItemsListViewModel({ initialItems: [] });
        expect(vm.state.value).toEqual({ status: "empty", items: [] });
    });
});
```

```swift
// Swift Testing, iOS
@Suite("vm.items.list")
struct ItemsListViewModelTests {
    @Test("[scenario.items.list.empty] shows empty state when no items exist")
    func emptyState() async {
        let vm = ItemsListViewModel(client: MockClient(returning: []))
        await vm.load()
        #expect(vm.status == .empty)
    }
}
```

```kt
// kotlin.test, Android
@Tag("spec:vm.items.list")
class ItemsListViewModelTest {
    @Test
    @DisplayName("[scenario.items.list.empty] shows empty state when no items exist")
    fun emptyState() = runTest {
        val vm = ItemsListViewModel(MockClient(returning = emptyList()))
        vm.load()
        assertEquals(UiState.Empty, vm.state.value)
    }
}
```

### Verify RED — watch it fail

**Mandatory. Never skip.** Run the test command. Confirm:

- It **fails**, not errors out (failing assertion ≠ undefined symbol).
- The failure message matches what you expect.
- It fails because the **feature is missing**, not because of a typo or import error.

If the test passes immediately, you're testing existing behavior — fix the test.
If the test errors, fix the error and re-run until it fails for the right reason.

### GREEN — minimal code

Write the simplest code that makes the failing test pass.

- No defensive `if` for cases not yet tested.
- No options objects, configuration, or hooks for future flexibility (YAGNI).
- No "while I'm here" refactors of unrelated code.

### Verify GREEN — watch it pass

Run the test. Confirm:

- It passes.
- All other tests in the suite still pass.
- Output is pristine — no warnings, no leaked logs, no "test passed but skipped".

### Refactor

Now that you're green, clean up. Remove duplication, improve names, extract helpers. Keep tests green throughout — every change should leave the suite passing. Do not add new behavior.

## Invariants get a property, not just examples

When a spec states an invariant — something that must hold for **all** valid inputs, not just the ones you happened to think of — the test for it **is a property-based test**. Hand-picked examples alone are insufficient: they prove the cases you imagined, and the `adversarial-review` stage will flag an invariant covered only by examples, because it hunts exactly the inputs your examples skipped. Write the property; keep a few examples beside it for documentation.

The trigger is concrete: a `domain.<entity>` spec's **Invariants** section that says "always", "never", "for any", or "for all". Each such invariant earns a property:

- "name is non-empty after trimming" → for all strings that are blank after trimming, validation rejects.
- round-trip → for all valid items, `decode(encode(item))` equals `item`.
- idempotence → for all inputs, `normalize(normalize(x))` equals `normalize(x)`.

```ts
// Vitest + fast-check, web
import { describe, it, expect } from "vitest";
import * as fc from "fast-check";
import { validateItem } from "./item";

describe("domain.item", () => {
    // [scenario.item.name-required] no blank-after-trim name ever validates
    it("[scenario.item.name-required] rejects any blank-after-trim name", () => {
        fc.assert(
            fc.property(fc.stringOf(fc.constantFrom(" ", "\t", "\n")), (blank) => {
                expect(validateItem({ id: "1", name: blank }).ok).toBe(false);
            }),
        );
    });
});
```

Per-platform property runners: **fast-check** (web/TS), **SwiftCheck** or parameterized `@Test(arguments:)` (Apple), **kotest-property** (Android), **FsCheck** (C#), **proptest** (Rust).

Discipline that still applies:

- **Watch it fail first.** A property test is a RED test like any other — run it against the missing/wrong implementation and confirm it fails for the right reason before you make it pass.
- **Keep the example tests too.** They document the specific Gherkin scenarios and read clearly. The property is the safety net underneath them, not a replacement for the scenario tests.
- **Tag it** with the spec ID and the scenario sub-ID it most directly defends, same as any other test.
- **Don't force a property where there isn't one.** A single enum mapping, a constant, UI formatting — those are example-shaped. Properties are for universally-quantified invariants, not for everything.

## Why order matters

> "I'll write tests after to verify it works."

Tests written after the implementation **pass immediately**. That proves nothing:

- Might test the wrong thing
- Might test what you implemented, not what's required
- Might miss edge cases you forgot
- You never saw it catch a bug

Test-first forces you to **see the test fail**, which proves the test actually tests something.

## Tagging discipline

Every test in this repo carries the spec ID it verifies. The exact form per platform is in `apps/<platform>/CLAUDE.md` and `specs/CONVENTIONS.md`. Summary:

| Platform              | Where the spec ID lives                     | Where the scenario sub-ID lives              |
| --------------------- | ------------------------------------------- | -------------------------------------------- |
| Web (Vitest)          | `describe('vm.items.list', ...)` block name | `it('[scenario.<id>] ...')` test name prefix |
| iOS (Swift Testing)   | `@Suite("vm.items.list")`                   | `@Test("[scenario.<id>] ...")` display name  |
| Android (kotlin.test) | `@Tag("spec:vm.items.list")`                | `@DisplayName("[scenario.<id>] ...")`        |

If a test doesn't carry these tags, drift detection can't find it. Don't skip the tags.

## Common rationalizations

| Excuse                            | Reality                                                                                             |
| --------------------------------- | --------------------------------------------------------------------------------------------------- |
| "Too simple to test"              | Simple code still breaks. The test takes 30 seconds.                                                |
| "I'll test after"                 | Tests passing immediately prove nothing.                                                            |
| "Already manually tested"         | Manual ≠ automated. No record, can't re-run.                                                        |
| "Deleting work is wasteful"       | Sunk cost. Keeping unverified code is technical debt.                                               |
| "Need to explore first"           | Fine — throw the exploration away, then start with TDD.                                             |
| "Test hard = design unclear"      | Listen to the test. Hard to test means hard to use.                                                 |
| "My examples cover the invariant" | Examples cover the inputs you thought of. "For all" means the ones you didn't — write the property. |

## Red flags — stop and start over

- Code before the test
- Test added "after we ship"
- Test passes immediately
- Can't explain why the test failed
- "Just this once"
- "Keep as reference, write tests, then adapt"

All of these mean: **delete the code, start with TDD**.

## When stuck

| Problem                | Solution                                             |
| ---------------------- | ---------------------------------------------------- |
| Don't know how to test | Write the wished-for API. Write the assertion first. |
| Test too complicated   | Design too complicated. Simplify the interface.      |
| Must mock everything   | Code too coupled. Use dependency injection.          |
| Test setup huge        | Extract helpers. Still big? Simplify the design.     |

## Verification checklist

Before marking work complete:

- [ ] Every behavior has at least one test
- [ ] Every stated invariant ("always" / "for all") has a property-based test, not just examples
- [ ] Watched each test fail before implementing
- [ ] Each test failed for the expected reason
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass
- [ ] Output pristine (no warnings, no leaked logs)
- [ ] Tests use real code (mocks only when unavoidable)
- [ ] Tags are correct (spec ID + scenario sub-ID)

Can't tick every box? You skipped TDD. Start over.

## Commit

Each green-refactor cycle is a natural commit boundary. Once the suite is green and the refactor is clean, commit before starting the next red. See `.claude/rules/commit-discipline.md`.

Typical shape:

- **One commit per behavior** when test and impl are tightly bound: `feat: <behavior>` or `fix: <bug>`. The commit contains the new test and the minimum code to make it pass.
- **Split into two commits** when the failing test is valuable on its own (e.g. a regression test that should land even if the fix takes longer): `test: add failing test for <bug>` then `fix: <bug>`.

Do **not** commit while red. A WIP commit between red and green is the wrong answer — finish the cycle, then commit.

## Related skills

- `implementing-a-spec` — the workflow that invokes this skill
- `verification-before-completion` — the gate before claiming the work is done
- `systematic-debugging` — for when a test fails for a reason you don't yet understand
