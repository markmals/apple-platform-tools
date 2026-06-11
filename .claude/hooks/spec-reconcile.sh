#!/usr/bin/env bash
# PostToolUse: surface spec/impl reconciliation reminders.
#  - When a spec file under specs/ or features/<n>/ is edited:
#    list implementations that reference its ID; suggest /sdd-apply per platform.
#  - When a code file is edited:
#    if it carries `SPEC: <id>` pointers, point at the corresponding spec file.
#
# Output is injected via hookSpecificOutput.additionalContext, so the agent
# sees the reminder but isn't forced to act. Silent when nothing matches.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0

cd "$CLAUDE_PROJECT_DIR"

notes=""

# Spec edited → list impl references
if [[ "$file_path" == */specs/*.md ]] || [[ "$file_path" == */features/*/*.md ]]; then
    spec_id=$(awk -F'[[:space:]]*:[[:space:]]*' '/^id:/ { print $2; exit }' "$file_path" 2>/dev/null || true)
    [[ -z "$spec_id" ]] && spec_id=$(basename "$file_path" .md)

    refs=$(rg -l --no-heading "SPEC:[[:space:]]*${spec_id}\b" apps/ services/ 2>/dev/null || true)
    if [[ -n "$refs" ]]; then
        notes="Spec '$spec_id' was edited. Implementations referencing it may now drift:
$refs

Consider running /sdd-apply $spec_id <platform> for each affected platform, or /sdd-drift to see drift across platforms."
    fi
fi

# Impl edited → list spec files referenced
if [[ "$file_path" =~ \.(swift|ts|tsx|kt|kts|js|jsx|mjs)$ ]]; then
    spec_ids=$(grep -oE 'SPEC:[[:space:]]*[a-zA-Z0-9._-]+' "$file_path" 2>/dev/null | awk '{print $NF}' | sort -u || true)
    for id in $spec_ids; do
        [[ "$id" == "manual" ]] && continue
        spec_file=$(rg -l --no-heading "^id:[[:space:]]*${id}\b" specs/ features/ 2>/dev/null | head -1 || true)
        if [[ -n "$spec_file" ]]; then
            notes="${notes}${notes:+

}Impl edited; spec to verify still matches: $spec_file (id: $id)"
        fi
    done
fi

if [[ -n "$notes" ]]; then
    jq -n --arg ctx "$notes" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
fi

exit 0
