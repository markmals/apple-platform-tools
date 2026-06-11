# Enforcement Hierarchy

> **This file is _referenced_, not `@included`.** It does not load on every session — it is the standard to apply when deciding _where a convention lives_. Linked from the root `CLAUDE.md` ("What lives where") and `/setup`.

A rule an agent must _remember_ is the weakest kind of rule. Under load, prose gets skipped — the more conventions a `SKILL.md` carries, the more reliably some get ignored. The durable conventions in this repo are the ones a machine enforces, not the ones an agent is asked to keep in mind. So when you reach for a new rule, reach down this hierarchy first.

## The tiers — strongest to weakest

- **Tier 0 — Hooks** (`.claude/hooks/`). Deterministic; the agent cannot forget or skip them. `block-generated.sh` refuses edits to generated output; `format-on-edit.sh` / `stop-lint.sh` dispatch the platform's `fmt`/`lint`; `spec-reconcile.sh` injects drift reminders; `scoped-commits.sh` rejects a commit whose scope isn't a defined spec/feature ID, platform, or harness area. If a rule can be a hook, it should be.
- **Tier 1 — Commands & tasks.** The `sdd-*` commands and the `mise` `fmt`/`lint`/`test` tasks. Agent-invoked, but the _behavior_ is codified, not recalled. Drift, coverage, and verification belong here.
- **Tier 2 — Templates** (`.claude/templates/`). Shape the work so the correct thing is the path of least resistance — the frontmatter, the reverse pointer, the scenario tags all come pre-wired.
- **Tier 3 — Prose** (`SKILL.md` files, the `rules/` files). The rule the agent must read and remember. Necessary for judgment that can't be mechanized, but the tier most likely to be missed.

## The rule

- **Before adding a prose rule, ask whether a hook or `sdd-*` command could enforce it deterministically.** If yes, build that instead of writing the prose.
- **Where a hook already enforces a rule, don't also state it in prose.** The duplicate prose rots — it drifts from the hook and competes for attention. Delete it.
- **Promote to a mechanism only when the check is cheap, deterministic, and cross-platform.** Subjective judgment — good naming, the right abstraction, whether a deviation still makes sense — stays prose. A linter cannot make that call, and pretending it can produces noise.

## Worked example — `/sdd-drift`

The three sync invariants in `specs/CONVENTIONS.md` → "Drift detection" are exactly the kind of rule that belongs in a mechanism, not prose: _reverse-pointer presence per platform_, _spec mtime ≤ newest pointer-bearing file mtime_, _a passing scenario-tagged test per platform_. All three are cheap, deterministic, and cross-platform. Today they are enforced by an agent running `rg` by hand, and `/sdd-drift` is "scaffolded; implementation deferred." Those three checks are the canonical promotion target: when `/sdd-drift` graduates from scaffold to implementation, mechanizing them is what it does.

## The caveat this repo earns

Several `sdd-*` commands are deliberately agent-driven for now (no automation yet), and the skills are intentionally prose-light. This principle is not a mandate to mechanize everything at once — it is the standard for deciding where the _next_ convention lands. Apply it at the repo's own bar: mechanize the cheap, deterministic, cross-platform checks; leave judgment in prose.
