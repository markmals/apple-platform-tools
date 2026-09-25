# Commit Discipline

> **This file is `@included` from the root `CLAUDE.md`.** It loads on every session.
>
> **Note for users who copied this template:** the default policy here is that the agent commits at natural commit points. If you'd rather hold commit boundaries yourself, override this with a feedback memory like `"Don't run git commits — I'll handle them"` and the agent will stop committing.

The agent commits often, atomically, and with messages a human would write. Commits are how work becomes durable; treat them as a primary deliverable, not an afterthought.

## When to commit

A commit lands at a **natural commit point** — a moment where the working tree represents one coherent, internally consistent unit of work. Typical natural commit points:

- A failing test was written, then the implementation made it pass, and the test now passes. (Two commits if the test-then-implementation distinction matters; one commit if they're tightly bound.)
- A self-contained refactor is complete and all tests still pass.
- A spec was edited and the affected docs/templates re-checked.
- A configuration change was made and verified in the relevant tool.
- A feature folder was authored or extended and the agent ran `/sdd-analyze` against it.

Do **not** commit mid-task work. If tests are red, if the file is half-edited, if the change is incomplete — keep going (or stash and pivot). A WIP commit is the wrong answer; finish the thought, then commit.

## What goes in one commit

**One logical change per commit.** If you can describe the commit as "X and also Y", it's two commits.

Counter-examples that are _not_ one logical change:

- "Add the sdk-api check command and also bump swift-argument-parser"
- "Fix the headerdump timeout bug and reformat the file"
- "Implement command.sdk-api.check and command.sdk-api.members"

In each case, split. The dependency bump is its own commit. The reformat is either its own commit or, ideally, dropped because it has nothing to do with the bug.

## What goes in a good message

A commit message has three parts: **subject**, optional **body**, optional **trailer(s)**.

This repo uses **[Scoped Commits](https://scopedcommits.com/)**, not Conventional Commits. The subject leads with the **scope** — the subsystem, area, or module the commit touches — because in a spec-driven repo, _where_ a change lands is the first thing a reader (or an incident responder) needs to know. This repo is spec-heavy: most commits are scoped to a single spec/feature ID, and that ID doubles as a reverse pointer to the behavior the commit touches.

### Subject

The shape is **`<scope>: <description>`**.

The **description**:

- Imperative, present tense: "add", "fix", "remove" — not "added" or "adds".
- The whole subject (scope included) stays under ~72 characters.
- No trailing period.
- Specific. "fix bug" is useless; "reject stale node ids in node" is useful.

The **scope** names what the commit touches. Scoped Commits leaves the vocabulary to the project; in this repo a scope must be one of the **defined** scopes below — and `scoped-commits.sh` enforces that mechanically, rejecting a subject whose scope isn't real (see `.claude/rules/enforcement-hierarchy.md`). The set isn't a hand-maintained list: the hook derives it from the filesystem at commit time, so adding a spec, a feature folder, or a `Sources/` target makes it a usable scope automatically.

| Scope | Use for |
| --- | --- |
| a **spec / feature ID** — `command.sdk-api.check`, `domain.agent-cli`, `story.headerdump.dump-framework`, `error.uitool.stale-node` | A change scoped to one spec's behavior. **The common case here.** The scope is a **reverse pointer to that `id:`** — same discipline as `// SPEC:`. |
| a **tool or library target** — `sdk-api`, `sdk-search`, `headerdump`, `redump`, `uitool`, `UIToolBoot` | A tool-level change not tied to one spec (a CLI-wide refactor, a manifest tweak). Derived from `Sources/`. Library targets are PascalCase (`AgentCLI`, `MachOFoundation`, …) and scopes are lowercase, so scope library changes by the library's `domain.*` spec ID (e.g. `domain.agent-cli`). |
| `specs` | Cross-cutting spec files (`CONVENTIONS`, `ARCHITECTURE`, `STACK`, cross-cutting `models/`). |
| `features/<tool>` | Authoring or extending a tool's feature namespace under `Features/<tool>/`. |
| a harness area — `hooks`, `skills`, `commands`, `agents`, `templates`, `rules`, `docs`, `mise` | Changes to the harness's own machinery. |
| `treewide` | A genuinely repo-wide sweep with no single home. |

The IDs come straight from the `id:` frontmatter in `Specs/` and `Features/` — list them with `grep -rhE '^id:' Specs Features`. When a change spans more than one area, prefer the **broadest scope that still describes it**; only fall back to a comma-separated list (`command.sdk-api.check, command.sdk-api.members: …`) when no single scope fits, and to `treewide` for a true global sweep. A ticket number, when there is one, goes in parentheses after the scope: `uitool (PROJ-12): …`.

Examples:

- `command.sdk-api.check: report the minimum OS for a symbol`
- `domain.agent-cli: add JSON-Lines streaming to the output contract`
- `specs: clarify per-tool feature namespacing in CONVENTIONS`
- `headerdump: cache the dyld shared cache parse across images`
- `hooks: derive commit scopes from Sources/ targets`

Reverts, merges, and other mechanical commits don't have to follow this shape — format them however is clearest.

### Body

Optional. Use it when the WHY isn't obvious from the subject. Wrap at ~72 characters. Explain:

- The motivation (what user-facing problem or spec change this addresses)
- Any non-obvious trade-offs
- Anything a future reader would want to know that the diff doesn't show

Skip the body for trivial changes.

### Trailer(s)

Optional `Key: value` lines at the end of the message. Use for:

- Cross-references: `Refs: story.headerdump.dump-framework`, `Spec: command.sdk-api.check`
- A ticket, if you'd rather not put it in the scope: `Ticket: PROJ-12`
- Breaking changes: `BREAKING CHANGE: <description>`
- Co-authorship (if collaborating)

## Staging

- **Never `git add .` or `git add -A`.** Both will sweep up files you didn't intend to include — untracked artifacts, env files, build outputs. Stage by explicit path.
- **`git status` before staging.** Look at what's in the working tree. Decide what belongs in this commit and stage exactly that.
- **Review the diff.** `git diff --staged` before committing. If something is in there you don't recognize or didn't intend, take it out.

## Pre-commit hooks

- If a pre-commit hook fails, **the commit didn't happen**. Fix the issue, re-stage, create a new commit. Do **not** `--amend` after a failed hook — there's nothing to amend.
- Never bypass with `--no-verify` unless the user explicitly asks. Hook failures are usually telling you something real.

## When to amend vs. new commit

- **Default: new commit.** Easier to reason about, easier to revert, easier to review.
- **Amend only when:** the previous commit is local (not pushed), the new change is genuinely part of the same logical unit, and amending makes the history clearer (not just smaller).

## What never to commit

- Secrets (`.env`, credential files, API keys). If you see these in `git status`, stop and warn the user.
- Build outputs (`dist/`, `.build/`, `DerivedData/`). The `.gitignore` should already exclude these — if it doesn't, fix the gitignore in its own commit.
- The runtime cluster's build artifacts (`*.dylib`, `*.framework`) — they are built from source on install, not committed; `.gitignore` excludes them.
- Personal IDE config (`.vscode/`, `.idea/`). Unless the user explicitly asks.
- Large binaries unless the project explicitly tracks them.

## Frequency

Prefer **many small commits** over a few large ones. Five focused commits with clear messages beat one giant "implement the headerdump feature" commit every time. Small commits are easier to review, revert, cherry-pick, and reason about months later.

## Push policy

Committing is one thing; pushing is another. **Do not push unless the user asks** — even if commits are clean. The user controls when work goes upstream.
