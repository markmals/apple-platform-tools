---
description: List spec IDs whose implementation has drifted from the spec.
argument-hint: (no arguments)
---

# /sdd-drift

You are detecting drift across the package.

## Intent

Identify specs and implementations that are out of sync. Drift takes several forms:

1. **Spec changed after impl was last touched.** The spec's `mtime` is newer than the most recent `mtime` of any file referencing it. Likely the impl needs updating.
2. **Impl changed without spec update.** The impl files referencing a spec have all been touched after the spec, _and_ their behavior may have changed. Likely the spec needs updating.
3. **Orphaned impl.** A file references a spec ID that no longer exists.
4. **Unimplemented spec.** A spec exists with no reverse pointer anywhere in `Sources/`.
5. **Untagged impl.** A file in `Sources/` has no `// SPEC:` annotation and is not in the allowlist of "manual" code.

## Steps

1. **Walk all spec files** under `Specs/` and `Features/`. Build a map of `id → {file_path, mtime}`.
2. **Walk `Sources/`.** For each source file:
    - If it has `// SPEC: <id>`, record the pair.
    - If it has `// SPEC: manual`, ignore it.
    - If it has neither, flag as untagged (case 5).
3. **Compute drift cases 1–4** from the cross-product of the two walks.
4. **Emit a report** grouped by drift type, with the relevant file paths and IDs.

## Output format

```
DRIFT REPORT
============

[1] Spec changed after impl (N)
  - <spec-id>  spec mtime: <ts>  newest impl mtime: <ts>
    <impl files>
  ...

[2] Impl changed without spec update (N)
  ...

[3] Orphaned impl (N)
  ...

[4] Unimplemented spec (N)
  ...

[5] Untagged impl files (N)
  ...
```

## Implementation status

Manual reasoning until tooling lands. A simple `rg` + `find -newer` combo suffices for cases 1–3; for cases 4–5, walk both trees and diff.
