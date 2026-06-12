# Apple Platform Tools

@.claude/rules/code-quality.md @.claude/rules/commit-discipline.md @.claude/rules/spec-conventions.md

A monorepo of Swift packages and CLIs that help **coding agents and humans** do Apple-platform development (macOS, iOS, iPadOS, watchOS, tvOS; AppKit, UIKit, SwiftUI, SwiftData, Core Data). One SwiftPM package, one executable target per tool, library targets for the shared spine. Every tool is **agent-first** and obeys one machine contract — deterministic JSON on stdout, diagnostics on stderr, exit codes as the control channel (the `AgentCLI` library makes this a dependency, not a memory).

## How this repo works

**Specs are the source of truth.** Domain models, command behaviors, errors, stories — all live as markdown in `Specs/` (cross-cutting) and `Features/<tool>/<NNNN>-<slug>/` (feature-scoped, namespaced by tool). The implementation carries `// SPEC: <id>` reverse pointers back to them.

If you're tempted to encode a behavioral contract only in code, write a spec instead.

**Read these before doing anything substantial:**

1. `Specs/CONVENTIONS.md` — spec format, ID taxonomy, frontmatter, reverse pointers, drift detection. **This is the contract.**
2. `Specs/ARCHITECTURE.md` — the three clusters, the shared foundations, the topology, the purity boundary, the dual-use posture.
3. `Specs/STACK.md` — the toolchain catalog.
4. `HANDOFF.md` — the full design doc the specs are derived from.

### Three places work comes from

1. **Specs and tests** — building or evolving behavior. `/sdd-apply`, `/sdd-verify`, `/sdd-cover`.
2. **Drift** — spec and implementation out of sync. `/sdd-drift`. Surfaced from reverse pointers and mtimes.
3. **Sub-spec defects** — local cosmetic / quirk issues the spec deliberately doesn't cover. Tracked in `DEFECTS.md`, filed via `/sdd-defect`, drained via `triaging-defects`. This file should want to be empty.

## Layout

```
.
├── CLAUDE.md            ← this file
├── Package.swift        ← one package; library + executable targets
├── mise.toml            ← fmt / lint / build / test tasks
├── .claude/             ← agents, sdd-* commands, hooks, rules, skills, templates
├── Specs/               ← cross-cutting specs (CONVENTIONS, ARCHITECTURE, STACK)
├── Features/<tool>/     ← feature-scoped specs as <NNNN>-<slug>/, per tool
├── Sources/
│   ├── AgentCLI/        ← the machine contract (JSON, exit codes, output discipline)
│   ├── MachOFoundation/ ← Mach-O + dyld-shared-cache reading
│   ├── RuntimeKit/      ← headless ObjC-runtime reflection + AppKit walker
│   ├── SDKIndex/        ← symbol-graph extraction/query + HIG pattern search
│   └── <tool>/          ← one executable per tool (sdk-api, sdk-search, headerdump, redump, uitool, …)
└── Tests/
```

The three capability clusters — **static binary analysis** (`headerdump`, `redump` on `MachOFoundation`), **live runtime introspection** (`uitool` on `RuntimeKit`), **SDK knowledge** (`sdk-api`, `sdk-search` on `SDKIndex`) — are described in `Specs/ARCHITECTURE.md`. Reach for them cheapest-first: SDK knowledge → static analysis → live injection.

## Working with specs

- **Reverse pointers are mandatory.** Every unit that realizes a spec carries `// SPEC: <id>`. Tests are tagged with the spec IDs they verify. See `Specs/CONVENTIONS.md`.
- **Deviations are explicit.** `// SPEC: <id> (deviates: <reason>)`; `// SPEC: manual` for incidental code.
- **Stories use Gherkin** with the coding agent as the user. Scenarios have stable sub-IDs tests trace back to. See `writing-user-stories`.
- **Test pure-first.** Each tool's pure core (JSON projection, ranking, grammar, Mach-O structure interpretation) is unit-tested on any Mac with checked-in fixtures or an embedded corpus — no privileges, no network. Effectful behavior is verified against a tool-appropriate oracle (uitool: the `SampleAppKit` known-geometry app under `DYLD_INSERT_LIBRARIES`; headerdump: a known framework; sdk-api: a checked-in symbol graph). If a behavior needs injection or a paid disassembler to test, the purity boundary was drawn wrong.

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

`/sdd-reconcile` ships but is inert (each tool is its own vertical — no cross-platform projection to reconcile). These commands are agent-driven (no automation yet — `rg`, `Edit`, `AskUserQuestion`).

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
| `macos-development` | Writing Swift/ObjC code. SwiftPM + ArgumentParser + Swift Testing + ObjC interop + codesign idioms; the AppKit-introspection + injection idioms apply to the runtime cluster (`uitool`/`RuntimeKit`). |

## Local tooling

`mise` drives tasks. `mise tasks` lists them; the contract is `fmt` / `lint` / `build` / `test`. The `format-on-edit` and `stop-lint` hooks dispatch to `fmt` / `lint`.

## MCP / IDE bridge

**Xcode external agent access** (per-machine, local config — not committed) exposes building, testing, and the code model over MCP. Enable it in Xcode and register it in your user or `.mcp.local.json`. See `macos-development`.

## What lives where

| Question | Where |
| --- | --- |
| "What's a spec ID look like?" | `Specs/CONVENTIONS.md` |
| "How do I add a feature / a new tool?" | `Specs/CONVENTIONS.md` → "Adding a new feature" |
| "What's the architecture / the clusters / the dual-use posture?" | `Specs/ARCHITECTURE.md` |
| "What toolchain does a given tool use?" | `Specs/STACK.md` |
| "The full design rationale?" | `HANDOFF.md` |
| "How do I write a user story?" | `.claude/skills/writing-user-stories/SKILL.md` |
| "Should this rule be a hook, command, or prose?" | `.claude/rules/enforcement-hierarchy.md` |
