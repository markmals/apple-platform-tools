# Feature Template

This directory holds the **canonical templates** for a new feature. When starting a feature, copy the structure here into `Features/<tool>/<NNNN>-<slug>/` and replace the placeholders.

## Layout

```
.claude/templates/feature/
├── README.md                         ← this file
├── NARRATIVE.md                      ← single file per feature
├── stories/STORY.md                  ← copy + rename per story
├── use-cases/USE_CASE.md             ← copy + rename per use case
├── user-flow/USER_FLOW.md            ← copy + rename per flow
├── models/MODEL.md                   ← copy + rename per model
├── view-models/VIEW_MODEL.md         ← copy + rename per view model
├── commands/COMMAND.md               ← copy + rename per CLI command
└── errors/ERROR.md                   ← copy + rename per error
```

## How to use

1. Pick the tool and the next number: `Features/<tool>/<NNNN>-<slug>/`. Numbering restarts per tool; slug is kebab-case.
2. Copy this directory's structure into the new feature directory:
    ```sh
    mkdir -p Features/<tool>/<NNNN>-<slug>/{stories,use-cases,user-flow,models,view-models,commands,errors}
    cp .claude/templates/feature/NARRATIVE.md Features/<tool>/<NNNN>-<slug>/NARRATIVE.md
    ```
3. Replace placeholders in the copied files:
    - `<tool>` — the executable's name (e.g. `sdk-api`, `headerdump`, `flexscope`)
    - `<feature-slug>` — the kebab-case slug (e.g. `dump-framework`)
    - `<id>` — a stable dotted ID (e.g. `story.headerdump.dump-framework`)
    - Section content
4. For each new spec instance (story, model, etc.), copy the appropriate `<KIND>.md` template into the matching subdirectory and rename to `<id>.md` (using dots in the filename: `story.headerdump.dump-framework.md`).
5. See `Specs/CONVENTIONS.md` for ID rules.

## What about specs?

There is no separate spec template directory for cross-cutting specs because the singleton cross-cutting specs (`ARCHITECTURE.md`, `STACK.md`, `CONVENTIONS.md`) already exist. For promoted models or other items, copy the relevant feature template (e.g. `models/MODEL.md`) into `Specs/models/<id>.md` and update the frontmatter.
