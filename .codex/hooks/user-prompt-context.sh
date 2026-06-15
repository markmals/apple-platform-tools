#!/usr/bin/env bash
# UserPromptSubmit: inject current branch + uncommitted changes so commits at
# natural points are obvious, plus a count of open entries in the root
# DEFECTS.md. The hook surfaces presence; the human decides when to drain
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

# Defect summary: count `### ` entries under `## Open` in the root DEFECTS.md.
# Comments inside <!-- ... --> blocks are ignored.
if [[ -f DEFECTS.md ]]; then
    count=$(awk '
        /^## Open/ { in_open=1; next }
        /^## / && in_open { in_open=0 }
        /^<!--/ { in_comment=1 }
        in_comment && /-->/ { in_comment=0; next }
        in_comment { next }
        in_open && /^### / { n++ }
        END { print n+0 }
    ' DEFECTS.md)
    if [[ "$count" -gt 0 ]]; then
        context="${context}

Open defects (DEFECTS.md): ${count}"
    fi
fi

jq -n --arg ctx "$context" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
