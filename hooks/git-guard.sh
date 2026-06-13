#!/bin/bash
# PreToolUse(Bash) — block blanket git staging.
#
# `git add -A` / `git add --all` / `git add .` stage everything, which can sweep
# unrelated uncommitted work into a commit. This guard denies those and tells the
# caller to stage specific paths instead. Specific-path adds pass through.
#
# Deny uses the current hookSpecificOutput contract; the reason is fed back to
# Claude so it rephrases rather than just hitting a wall.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Match `git add` with -A, --all, or a bare "." pathspec — but only when `git add`
# sits at a COMMAND boundary (line start, or after ; && |), so the pattern appearing
# inside a quoted commit message (-m "... git add -A ...") doesn't false-trigger.
# Chains like `cd x && git add -A` are still caught; `git add <path>` passes through.
if printf '%s' "$CMD" | grep -qE '(^|[;&|])[[:space:]]*git[[:space:]]+add[[:space:]]+([^&|;]*[[:space:]])?(-A|--all|\.)([[:space:]]|$)'; then
  jq -n --arg cmd "$CMD" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Blocked blanket git staging: `" + $cmd + "`. Stage specific paths instead (git add <path> …) and confirm no unrelated WIP is included.")
    }
  }'
fi
exit 0
