#!/usr/bin/env bash
# PreToolUse on Bash (gated by if: "Bash(git commit*)"):
# enforce a Scoped Commits subject — `<scope>: <description>` — where <scope> is
# a *defined* scope in this repo: a spec/feature ID (a reverse pointer to a real
# `id:` in specs/ or features/), an app/service dir, a harness area, a feature
# slug, a name listed in `.claude/commit-scopes`, or `treewide`. The set is
# derived from the filesystem at commit time — adding a spec, an `apps/<x>` dir,
# or a `.claude/commit-scopes` line makes that scope usable with no list to edit.
# Handles `git commit -m "..."` and the HEREDOC `-m "$(cat <<'EOF'
# ... )"` form; on commit forms whose subject can't be read confidently it
# enforces shape only, never a false rejection on membership.
# See https://scopedcommits.com/ and .claude/rules/commit-discipline.md.
set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"

# Skip non-commit invocations and amend / empty-message / help.
if ! echo "$command" | grep -qE '(^|[[:space:]])git[[:space:]]+commit\b'; then exit 0; fi
if echo "$command" | grep -qE '(--help|--allow-empty-message|--amend)'; then exit 0; fi

# Only inline messages are inspectable. A `-F`/`-C`/editor commit carries its
# message out of band — there's nothing to judge, so don't block it.
if ! echo "$command" | grep -qE '(^|[[:space:]])(-m|--message)([[:space:]]|=)' \
   && ! echo "$command" | grep -q '<<'; then exit 0; fi

fail() { echo "$1" >&2; exit 2; }

# Conventional Commits habit: a `type(subscope):` prefix — a word glued to `(...)`
# with no space. Scoped Commits is scope-first; a ticket goes after a space.
if echo "$command" | grep -qE '[a-z]+\([a-z0-9_./-]+\):[[:space:]]'; then
  fail "Looks like a Conventional Commits 'type(scope):' subject. This repo uses Scoped Commits — lead with a defined scope: '<scope>: <description>' (ticket after a space, e.g. 'web (PROJ-12): ...'). See .claude/rules/commit-discipline.md."
fi

# Shape gate — always enforced.
scope_re='[a-z0-9._/-]+([[:space:]]\([A-Za-z0-9-]+\))?'
if ! echo "$command" | grep -qE "${scope_re}(,[[:space:]]${scope_re})*:[[:space:]]"; then
  fail "Commit subject must be a Scoped Commit: '<scope>: <description>'. See .claude/rules/commit-discipline.md."
fi

# Read the subject from the two forms we can parse confidently; on anything else
# the shape gate stands and we skip membership (no false rejections).
if echo "$command" | grep -q '<<'; then
  subject=$(printf '%s\n' "$command" | awk '/<</{f=1;next} f&&NF{gsub(/^[ \t]+|[ \t]+$/,"");print;exit}')
elif [ "$(echo "$command" | grep -oE '(^|[[:space:]])-m([[:space:]]|=)' | wc -l | tr -d ' ')" = "1" ]; then
  subject=$(printf '%s\n' "$command" | sed -nE "s/.*-m[[:space:]]+[\"']//p" | head -1)
  subject=${subject%%\"*}; subject=${subject%%\'*}
else
  exit 0
fi
[ -n "${subject:-}" ] || exit 0

case "$subject" in
  *": "*) raw_scope=${subject%%": "*} ;;
  *) exit 0 ;;
esac

# Build the defined-scope set from the filesystem. (`|| true` so a no-match grep
# or an absent dir can't trip pipefail.)
#   - always: treewide, specs, and the harness areas
#   - app/service scopes: the immediate subdirs of apps/ and services/
#   - project scopes: non-comment lines of .claude/commit-scopes
#   - spec/feature scopes: every frontmatter `id:` in specs/ & features/
allowed=$(printf '%s\n' treewide specs agents commands hooks rules skills templates docs mise readme)
allowed+=$'\n'$({ ls -d "$root"/apps/*/ "$root"/services/*/ 2>/dev/null || true; } | sed -E 's#.*/(apps|services)/##; s#/$##')
if [ -f "$root/.claude/commit-scopes" ]; then
  allowed+=$'\n'$(grep -vE '^[[:space:]]*(#|$)' "$root/.claude/commit-scopes" 2>/dev/null || true)
fi
allowed+=$'\n'$(
  { grep -rlE '^id:' "$root/specs" "$root/features" 2>/dev/null || true; } \
  | while IFS= read -r f; do
      awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ {exit}
           /^---[[:space:]]*$/ {c++; if (c==2) exit; next}
           c==1 && /^id:[[:space:]]*/ {sub(/^id:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print; exit}' "$f"
    done
)
feature_slugs=$({ ls -d "$root"/features/*/ 2>/dev/null || true; } | sed -E 's#.*/features/##; s#/$##')

is_valid_scope() {
  local s
  s=$(printf '%s' "$1" | sed -E 's/[[:space:]]+\([A-Za-z0-9-]+\)$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
  grep -qxF "$s" <<<"$allowed" && return 0
  local slug
  for slug in $feature_slugs; do [ "$s" = "features/$slug" ] && return 0; done
  return 1
}

IFS=',' read -ra parts <<<"$raw_scope"
for p in "${parts[@]}"; do
  is_valid_scope "$p" || fail "Scope '$(printf '%s' "$p" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')' is not a defined scope. Use a spec/feature ID from specs/ or features/ (list: grep -rhE '^id:' specs features), an app/service dir, a harness area (hooks, skills, commands, agents, templates, rules, docs, mise, readme), a name from .claude/commit-scopes, a 'features/<slug>', 'specs', or 'treewide'. See .claude/rules/commit-discipline.md."
done

exit 0
