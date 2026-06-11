# Apple Platform Tools

@.claude/rules/code-quality.md @.claude/rules/commit-discipline.md @.claude/rules/spec-conventions.md

## How this repo works

**Specs are the source of truth.** Domain models, the IPC protocol, command behaviors, errors, stories — all live as markdown in `specs/` (cross-cutting) and `features/<NNNN>-<slug>/` (feature-scoped). The implementation carries `// SPEC: <id>` reverse pointers back to them.

If you're tempted to encode a behavioral contract only in code, write a spec instead.

**Read these before doing anything substantial:**

1. `specs/CONVENTIONS.md` — spec format, ID taxonomy, frontmatter, reverse pointers, drift detection. **This is the contract.**
2. `specs/ARCHITECTURE.md` — components, the purity boundary, IPC contract, injection model, security model.
3. `specs/STACK.md` — the toolchain catalog.
4. `HANDOFF.md` — the full design doc the specs are derived from.

### Three places work comes from

1. **Specs and tests** — building or evolving behavior. `/sdd-apply`, `/sdd-verify`, `/sdd-cover`.
2. **Drift** — spec and implementation out of sync. `/sdd-drift`. Surfaced from reverse pointers and mtimes.
3. **Sub-spec defects** — local cosmetic / quirk issues the spec deliberately doesn't cover. Tracked in `DEFECTS.md`, filed via `/sdd-defect`, drained via `triaging-defects`. This file should want to be empty.

## Layout

```
.
├── CLAUDE.md                  ← this file
├── mise.toml                  ← fmt / lint / build / test / sign / doctor tasks
├── .claude/                   ← agents, sdd-* commands, hooks, rules, skills, templates
├── specs/                     ← cross-cutting specs (CONVENTIONS, ARCHITECTURE, STACK)
└── features/                  ← (you create) feature-scoped specs as <NNNN>-<slug>/
```

Everything below `specs/` and `.claude/` is scaffolded when you start implementing — the spec layer drives that work.

## Working with specs

- **Reverse pointers are mandatory.** Every unit that realizes a spec carries `// SPEC: <id>`. Tests are tagged with the spec IDs they verify. See `specs/CONVENTIONS.md`.
- **Deviations are explicit.** `// SPEC: <id> (deviates: <reason>)`; `// SPEC: manual` for incidental code.
- **Stories use Gherkin** with the coding agent as the user. Scenarios have stable sub-IDs tests trace back to. See `writing-user-stories`.
- **Test against the oracle.** Injection-dependent behavior is verified against `SampleAppKit` (known frames/fonts/constraints), not first-party apps. Pure-core logic tests run on any Mac, no SIP changes.

## Slash commands

| Command | Purpose |
| --- | --- |
| `/sdd-apply <spec-id>` | Regenerate a spec's implementation + tests. |
| `/sdd-verify` | Run the Swift Testing suite; report which spec IDs pass. |
| `/sdd-drift` | List spec IDs whose impl is stale, plus impl files with no spec pointer. |
| `/sdd-cover <spec-id>` | Show a spec's implementation + which of its tests pass. |
| `/sdd-clarify <id>` | Resolve `[NEEDS CLARIFICATION]` markers in a feature or spec. |
| `/sdd-analyze <feature>` | Read-only cross-artifact consistency check for a feature folder. |
| `/sdd-challenge <spec-id>` | Adversarially review a spec's implementation — try to break it. |
| `/sdd-defect <desc>` | File a sub-spec defect into `DEFECTS.md` without breaking flow. |

`/sdd-reconcile` ships but is inert (single platform). These commands are agent-driven (no automation yet — `rg`, `Edit`, `AskUserQuestion`).

## Workflow skills

| Skill | When to invoke |
| --- | --- |
| `brainstorming-feature` | Before starting any new feature. Walks narrative → stories → models → view-models → flows → errors. |
| `writing-user-stories` | Authoring/reviewing a story file. Enforces Gherkin discipline. |
| `implementing-a-spec` | The default "how to write code" workflow. Per-spec subagent + three-stage review. Used by `/sdd-apply`. |
| `test-driven-development` | Writing any production code. No production code without a failing test first. |
| `adversarial-review` | The refutational third review stage. Assumes the code is broken and tries to break it. |
| `verification-before-completion` | Before claiming work complete. Run the verifying command this turn; evidence before claims. |
| `systematic-debugging` | Any bug or unexpected behavior. Root cause before fix. |
| `triaging-defects` | When `DEFECTS.md` is non-empty in a polish pass. |
| `macos-development` | Writing Swift/ObjC/AppKit code. SwiftPM + ArgumentParser + Swift Testing + AppKit-introspection + codesign idioms. |

## Local tooling

`mise` drives tasks. `mise tasks` lists them; the contract is `fmt` / `lint` / `build` / `test`. The `format-on-edit` and `stop-lint` hooks dispatch to `fmt` / `lint`.

## MCP / IDE bridge

**Xcode external agent access** (per-machine, local config — not committed) exposes building, testing, and the code model over MCP. Enable it in Xcode and register it in your user or `.mcp.local.json`. See `macos-development`.

## What lives where

| Question | Where |
| --- | --- |
| "What's a spec ID look like?" | `specs/CONVENTIONS.md` |
| "How do I add a feature?" | `specs/CONVENTIONS.md` → "Adding a new feature" |
| "What's the architecture / IPC contract / security model?" | `specs/ARCHITECTURE.md` |
| "What tool does flexscope use for X?" | `specs/STACK.md` |
| "The full design rationale?" | `HANDOFF.md` |
| "How do I write a user story?" | `.claude/skills/writing-user-stories/SKILL.md` |
| "Should this rule be a hook, command, or prose?" | `.claude/rules/enforcement-hierarchy.md` |
