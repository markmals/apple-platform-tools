---
id: conventions
kind: conventions
---

# Spec Conventions

This document defines the structure of specs in this repo. Every spec, every reverse pointer, every drift check assumes these rules. If you change anything here, audit every existing spec and pointer for consistency.

> **TL;DR:** Markdown files with YAML frontmatter, stable dotted IDs, one logical thing per file, and `// SPEC: <id>` comments in the code that implements them.

## Why specs at all

apple-platform-tools is a monorepo of independent CLIs, each its own **vertical**. Specs here pin _what must hold_ — each tool's JSON output contract, its exit-code map, each command's behavior, the determinism guarantees — independently of the Swift/ObjC that satisfies it. Code is cheap to regenerate against a sharp spec; the spec is the durable artifact.

The tools do not mirror one shared behavior across platforms; they are different tools that share a *contract* (the `AgentCLI` machine interface) and *foundations* (`MachOFoundation`, `RuntimeKit`, `SDKIndex`). So the discipline is vertical (spec → failing test → implementation → review → verification) per tool, not lateral (the same behavior reconciled across web/iOS/Android). The reconciliation machinery (`/sdd-reconcile`) is inert by design; the rest of the SDD vertical is fully in force.

Specs describe **what** must hold. Tests prove it. Implementations satisfy it. None of those three is the source of truth on its own.

## File and directory layout

```
specs/                          ← cross-cutting (used by ≥ 2 tools, or repo-wide)
├── ARCHITECTURE.md             ← singular; the whole monorepo
├── CONVENTIONS.md              ← this file
├── STACK.md                    ← the toolchain catalog
├── models/<id>.md              ← cross-cutting domain models (e.g. the AgentCLI contract)
└── view-models/<id>.md         ← cross-cutting view models (rare)

features/<tool>/<NNNN>-<slug>/  ← feature-scoped, namespaced by tool
├── NARRATIVE.md                ← singular per feature
├── README.md                   ← singular per feature; describes the folder
├── stories/<id>.md             ← one user story per file
├── use-cases/<id>.md           ← one concrete use case per file
├── user-flow/<id>.md           ← one interaction sequence per file
├── models/<id>.md              ← one domain model per file
├── view-models/<id>.md         ← one view model per file
├── commands/<id>.md            ← one CLI command's behavior per file
└── errors/<id>.md              ← one error catalog entry per file
```

### Per-tool namespacing

Features are grouped by tool: `features/<tool>/<NNNN>-<slug>/`, where `<tool>` is the executable's name (`flexscope`, `headerdump`, `sdk-api`, …). Numbering restarts per tool, so each tool owns a clean `0001…` sequence and the monorepo's growth stays legible. A feature slug is kebab-case.

### One logical thing per file

If a kind has multiple instances in a feature (multiple stories, multiple errors, multiple models), it gets a **directory** of `<id>.md` files. If a kind has exactly one instance per feature (the narrative), it stays a **file**. The directory name is the kebab-case equivalent of the kind name (`view-models/`, not `view_models/` or `viewModels/`).

### Cross-cutting vs feature-scoped

A spec lives in `features/<tool>/<n>/` until a _second_ consumer depends on it. At that point it gets **promoted**: the file moves to `specs/<kind>/<id>.md`, but its **ID does not change**. Reverse pointers in code stay valid through the move. The shared foundations (`AgentCLI`, `MachOFoundation`, `RuntimeKit`, `SDKIndex`) are the natural home of cross-cutting specs — the JSON contract, the Mach-O node model, the node-ID grammar.

The only specs that start cross-cutting are `ARCHITECTURE.md`, `STACK.md`, and this file.

## Frontmatter schema

Every spec file (in `specs/<kind>/` or `features/<tool>/<n>/<kind>/`, plus the singular files like `NARRATIVE.md`) starts with YAML frontmatter:

```yaml
---
id: <stable-dotted-id> # required, must match filename stem
kind: <one of the kinds below> # required
depends-on: [<id>, <id>, ...] # optional; specs this one references
status: draft | accepted # optional; default = accepted
---
```

The top-level singular files (`ARCHITECTURE.md`, `STACK.md`, `NARRATIVE.md` per feature, `CONVENTIONS.md`) use a special form:

```yaml
---
id: architecture # or stack, conventions, narrative.<tool>.<feature-slug>
kind: architecture # the kind matches the file's role
---
```

`depends-on` is a flat list of IDs. It is not transitive, not enforced by tooling yet, and exists primarily so a human or agent can grep for "what depends on `domain.macho-image`".

## Kind taxonomy

Kinds are the closed set of allowed `kind:` values, paired with their directory and ID prefix.

| Kind            | Directory       | ID prefix                            | One per file? | Notes                                                                  |
| --------------- | --------------- | ------------------------------------ | ------------- | ---------------------------------------------------------------------- |
| `narrative`     | (singular file) | `narrative.<tool>.<feature-slug>`    | yes           | One per feature.                                                       |
| `story`         | `stories/`      | `story.<tool>.<capability>`          | yes           | Authored using the `writing-user-stories` skill. Gherkin lives inline. |
| `use-case`      | `use-cases/`    | `usecase.<tool>.<scenario>`          | yes           | Concrete walkthrough; complements stories.                             |
| `flow`          | `user-flow/`    | `flow.<tool>.<action>`               | yes           | Step-by-step interaction sequence.                                     |
| `domain`        | `models/`       | `domain.<entity>`                    | yes           | Plain data shapes, invariants, validation rules.                       |
| `view-model`    | `view-models/`  | `vm.<tool>.<view>`                   | yes           | State, actions, transitions, derived values.                           |
| `command`       | `commands/`     | `command.<tool>.<verb>`              | yes           | One CLI command's behavior: flags, the work it does, projection, exit code. |
| `error`         | `errors/`       | `error.<tool>.<kind>`                | yes           | User-observable failure mode + recovery affordance.                    |
| `architecture`  | (singular file) | `architecture`                       | yes           | Cross-cutting; one for the monorepo.                                   |
| `conventions`   | (this file)     | `conventions`                        | yes           | Cross-cutting; one for the monorepo.                                   |

A kind can grow over time (e.g., `migration` for schema changes), but adding a kind is a deliberate change to this document, not an ad-hoc choice. Cross-cutting domain models (the `AgentCLI` contract, the Mach-O image model) use the bare `domain.<entity>` prefix with no tool segment, since they belong to a foundation, not a tool.

## Stable IDs

IDs are dotted, lowercase, hierarchical, and stable. The first segment is the kind prefix; the rest narrow to a specific instance.

**Good:** `domain.macho-image`, `vm.flexscope.tree`, `story.headerdump.dump-framework`, `command.sdk-api.check`, `error.flexscope.stale-node`

**Bad:** `Image`, `headerdump/dump`, `vm-flexscope-tree`, `viewmodel.flexscope.tree` (use `vm.`)

### Stability rules

- IDs are immutable once an implementation references them. Renaming requires a deliberate migration: update the spec ID, every `// SPEC:` reference, and every test tag in one commit.
- IDs do not change when a spec is promoted from `features/` to `specs/`.
- IDs name the abstract behavior, not the file path. The tool segment in a `command`/`story`/`error` ID identifies the owning tool; a cross-cutting `domain` ID has no tool segment.

### Filename = ID stem

Filename matches the trailing segment of the ID, with dots → hyphens between segments but preserved within the stem:

- `domain.macho-image` → `models/macho-image.md`
- `story.headerdump.dump-framework` → `stories/headerdump.dump-framework.md`
- `vm.flexscope.tree` → `view-models/flexscope.tree.md`

Dots are legal in macOS/Linux filenames and survive grep, git, and most editors. Keep them.

## Reverse pointers

Every implementation file, class, or function that realizes a spec carries the spec ID in a comment.

### Per-language form

Most tools are **Swift**. The runtime cluster (`RuntimeKit`, `FlexScopeBoot`) is **Objective-C / C** (it touches the ObjC runtime and AppKit on the target's main thread). All use the same `// SPEC:` line comment.

```swift
// SPEC: command.sdk-api.check
struct Check: AsyncParsableCommand { /* ... */ }
```

```objc
// SPEC: domain.appkit-walker
@implementation FLEXAppKitWalker
@end
```

```c
// SPEC: domain.injection
__attribute__((constructor)) static void flexscope_boot(void) { /* ... */ }
```

### Granularity

- One reverse pointer per spec realization, attached to the smallest unit that fully realizes the spec (usually a class or top-level function, sometimes a module).
- Multiple files may reference the same ID if the implementation is split across them.
- Do not annotate every helper function — only the unit that fulfills the contract.

### Tests carry the same IDs

Every behavioral test is tagged with the spec IDs it verifies.

- **Swift Testing (primary):** a `@Suite("command.sdk-api.check")` per spec ID and a `@Test("[scenario.sdk-api.check.exists] …")` display-name prefix per scenario. The `[scenario.<id>]` prefix is what drift tooling greps. (`.tags(.spec(…), .scenario(…))` also works if you prefer tag-based filtering.)
- **XCTest (ObjC, where `RuntimeKit` is exercised from ObjC):** a `// SPEC: <id>` comment on the test class and a `// [scenario.<id>]` comment above each `- (void)test…` method (ObjC selector names can't hold dots or brackets, so the sub-ID lives in the comment drift tooling greps).

The `[scenario.<id>]` prefix is mandatory because Gherkin scenarios in story files have their own sub-IDs (below) and tests must trace to a specific scenario, not just a story.

## Stories and scenarios

Stories follow the `writing-user-stories` skill. Each story file contains:

1. Frontmatter with `id: story.<tool>.<capability>`
2. The `As a / I want / So that` block
3. An `# Acceptance Criteria` section with Gherkin scenarios

Each scenario has a stable sub-ID derived from its position and intent:

```md
## Scenario 1: Checking a symbol that exists

<!-- id: scenario.sdk-api.check.exists -->

- Given the AppKit symbol graph is available
- When the agent checks `NSGlassEffectView.effectIsInteractive`
- Then the tool reports it exists with its minimum OS version
```

Sub-IDs follow the pattern `scenario.<tool>.<capability>.<short-name>`. Tests reference them in the `[scenario.id]` prefix.

### The actor is a coding agent (repo-wide)

The `writing-user-stories` skill requires the story actor to be a real human. **This repo's tools are agent-first by design**, so stories use **"As a coding agent"** as the sanctioned actor. The output shape, determinism, and exit-code contract of every tool exist to serve an agent, not a human at a terminal. The human steering the agent (named in each feature's `NARRATIVE.md`) remains the ultimate beneficiary; the coding agent is the direct, first-class user the verbs are shaped for. Reviewers read "coding agent" as the sanctioned actor here, not as a non-human-actor violation.

## Marking unspecified or ambiguous content

When authoring a spec, do **not** silently guess at unspecified details. Mark them inline with a `[NEEDS CLARIFICATION: <question>]` token:

```md
**FR**: `redump` returns disassembly via [NEEDS CLARIFICATION: IDA, Hopper, or whichever is installed — and what if neither is?].
```

Why: an LLM that fills in plausible-but-unverified details produces specs that _look_ complete but contain hidden assumptions. A spec sprinkled with `[NEEDS CLARIFICATION]` markers is more honest, easier to review, and forces a deliberate resolution step before implementation.

**Resolution:** the `/sdd-clarify <feature-or-spec-id>` slash command scans for these markers, surfaces the highest-priority questions to the user, and edits the answers back into the spec. A spec cannot be considered ready for `/sdd-apply` while `[NEEDS CLARIFICATION]` markers remain.

**When to use:**

- The user prompt didn't specify a behavior, constraint, or value.
- Two interpretations are equally plausible and you can't pick without input.
- A non-functional requirement (a dependency, a timeout, a performance target) is implied but not stated.

**When NOT to use:**

- For known-unknowns about implementation details (those belong in `// SPEC: <id> (deviates: <reason>)` comments, not in the spec).
- For "we'll figure this out later" placeholders for features outside the current scope (just don't write the spec yet).

## Deviation marker

When an implementation must differ from the spec — because of a tool constraint, idiom, or a deliberate choice — annotate the deviation:

```swift
// SPEC: command.sdk-api.check (deviates: caches the symbol graph under ~/Library/Caches, not /tmp)
```

```swift
// SPEC: manual
// Incidental code — no behavioral contract.
```

`(deviates: <reason>)` keeps the pointer live so drift detection still flags spec changes; the agent then decides whether the deviation still makes sense. `// SPEC: manual` opts out entirely, and is used sparingly for genuinely incidental code.

## Drift detection

A spec and its implementation are **in sync** when:

1. Every spec has at least one reverse pointer (or is intentionally not yet implemented).
2. The spec's mtime ≤ the most recent mtime of files containing reverse pointers to its ID.
3. Tests tagged with the spec's ID exist and pass.

Drift is detected by `/sdd-drift` (scaffolded; implementation deferred). The slash command outputs the IDs that fail any of the above.

All three invariants are mechanically checkable — reverse-pointer presence, an mtime comparison, a tagged-test lookup — yet they are still enforced by an agent running `rg` by hand. They are the canonical target for promotion to a real `/sdd-drift` implementation: cheap, deterministic, and uniform across tools, exactly the kind of rule that should live in a mechanism rather than in prose an agent must remember. See `.claude/rules/enforcement-hierarchy.md`.

## Reconciliation (inert)

`/sdd-reconcile` exists for repos where one behavior is mirrored across platforms and must be kept in step. Here, each tool is its own vertical and there is no such mirror, so reconciliation is **inert by design**. A tool's spec and implementation are kept in sync by the vertical loop (drift detection above), not by lateral reconciliation. If the monorepo ever grows a genuinely cross-platform capability (e.g. a behavior shared between the macOS and a future iOS `RuntimeKit` surface), this section gets revisited.

## Adding a new feature

1. Pick the tool and the next number: `features/<tool>/<NNNN>-<slug>/`. Slug is kebab-case.
2. Copy `.claude/templates/feature/` into the new feature directory.
3. Author `NARRATIVE.md` first (use the brainstorming-style narrative from interviews or product input).
4. Author stories from the narrative.
5. Derive use-cases, flows, models, view-models, errors as needed. Not every feature uses every kind.
6. Implement against the spec (see the `macos-development` and `implementing-a-spec` skills). Write the failing Swift Testing test first, tagged with the scenario sub-ID.
7. Verify with `/sdd-verify`, using a tool-appropriate oracle (checked-in fixtures, an embedded corpus, or `SampleAppKit` for injection-dependent behavior).

## Adding a new tool

A new tool is a new executable target plus its feature namespace:

1. Add the executable target to `Package.swift`, depending on `AgentCLI` and whichever foundation(s) it needs.
2. Create `features/<tool>/` and author its first feature as above.
3. If it introduces a genuinely shared capability, factor that into (or add) a foundation library rather than the tool target.
4. Register the tool in `ARCHITECTURE.md`'s cluster table.

## Adding a new spec kind

1. Add a row to the kind taxonomy table above.
2. Decide ID prefix and directory name.
3. Add a template file at `.claude/templates/feature/<dir>/<KIND>.md`.
4. Update `.claude/templates/feature/README.md`.
5. Update the file/directory layout diagram at the top of this document.
6. Commit the convention change before authoring any specs of the new kind.

## What is NOT a spec

These are reference material an agent may read, but not the spec layer. Do not put them under `specs/` or in a feature folder's spec subdirectories.

- Wireframes, mockups, visual designs (link from `NARRATIVE.md` if needed)
- Prototype code or sandbox repos
- Meeting notes, RFCs, decision logs (use a `docs/` directory if you need one)
- Analytics events, telemetry, observability — implementation concerns
- Local cosmetic / quirk defects (a noisy diagnostic, an awkward default, a polish issue) — these go in `DEFECTS.md`, not in specs. See the `triaging-defects` skill for the classifier that decides which side of the line an observation falls on.

If you find yourself writing implementation details into a spec, stop and ask: **is this a behavioral contract the tool must satisfy, or an incidental implementation choice?** A contract (an exit code, a JSON field, a determinism guarantee) is spec; an incidental choice (an internal helper, a log format) is not. The same test decides whether an observation belongs in `DEFECTS.md` (incidental) or in a spec amendment (contract).
