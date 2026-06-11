#!/usr/bin/env bash
# UserPromptSubmit: inject current branch + uncommitted changes so commits at
# natural points are obvious, plus a summary of any non-empty per-platform
# DEFECTS.md files. The hook surfaces presence; the human decides when to drain
# (via the triaging-defects skill).
set -euo pipefail

cd "$CLAUDE_PROJECT_DIR"

branch=$(git branch --show-current 2>/dev/null || echo "(detached)")
status=$(git status --short 2>/dev/null || true)

if [[ -n "$status" ]]; then
    context="Current branch: $branch
Uncommitted changes:
$status"
else
    context="Current branch: $branch (clean working tree)"
fi

# Defect summary: count `### ` headings under `## Open` in each DEFECTS.md.
# An entry is anything that looks like `### <title>` after the `## Open`
# marker. Comments inside <!-- ... --> blocks are ignored.
defect_summary=""
for f in apps/*/DEFECTS.md services/*/DEFECTS.md; do
    [[ -f "$f" ]] || continue
    count=$(awk '
        /^## Open/ { in_open=1; next }
        /^## / && in_open { in_open=0 }
        /^<!--/ { in_comment=1 }
        in_comment && /-->/ { in_comment=0; next }
        in_comment { next }
        in_open && /^### / { n++ }
        END { print n+0 }
    ' "$f")
    if [[ "$count" -gt 0 ]]; then
        # Trim the trailing /DEFECTS.md so the label is the platform dir.
        label=${f%/DEFECTS.md}
        defect_summary="${defect_summary}${defect_summary:+
}  ${label}: ${count}"
    fi
done

if [[ -n "$defect_summary" ]]; then
    context="${context}

Open defects:
${defect_summary}"
fi

jq -n --arg ctx "$context" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
