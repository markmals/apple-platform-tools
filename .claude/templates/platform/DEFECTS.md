# Defects — <platform>

> Sub-spec defects observed on this platform. Append on observation; delete on fix. This file should want to be empty.
>
> What belongs here: platform-local, observed defects that don't have a cross-platform behavioral contract — cosmetic issues, platform quirks, polish. If a defect turns out to describe behavior the spec _should_ have covered, promote it to a spec amendment via the `triaging-defects` skill and delete the entry.
>
> What does NOT belong here: spec gaps (use `[NEEDS CLARIFICATION]` during authoring, or amend the spec), cross-platform behavioral drift (use `/sdd-drift`), or open questions about intent (those go in the spec).

## Open

<!-- Entries land here. Each entry follows this shape:

### <short imperative title>
- observed: <YYYY-MM-DD>
- where: <file path or screen, e.g. apps/<platform>/App/Features/Items/ItemsListView.swift, or "ItemsListView on 4.7" devices">
- symptom: <one sentence — what the user sees>
- repro: <minimal steps to reproduce>
- screenshot: <optional path to a screenshot in apps/<platform>/.defects/>
- notes: <optional — hypothesis, related spec id, anything useful>

When you fix an entry, delete it. The fix commit is the durable record.
-->

- Screenshots referenced by entries go in `apps/<platform>/.defects/` (or `services/<platform>/.defects/` for backend platforms). Commit them alongside the entry; delete them when their entry is deleted. The `triaging-defects` skill enforces this cleanup.
- Don't add status fields, severity labels, or assignees. If an entry needs more structure than the shape above, it's probably a spec change, not a defect.

_(empty)_
