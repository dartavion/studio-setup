#!/bin/bash

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR="${CWD:-.}"

# Spawn a new WezTerm workspace if we start a session in a different repo inside WezTerm
if [ -n "$WEZTERM_PANE" ]; then
  CURRENT_WORKSPACE=$(wezterm cli get-workspace 2>/dev/null)
  REPO_NAME=$(basename "$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || echo "$(basename "$DIR")")")
  if [ -n "$REPO_NAME" ] && [ "$CURRENT_WORKSPACE" != "$REPO_NAME" ]; then
    wezterm cli spawn --new-window --workspace "$REPO_NAME" --cwd "$DIR" >/dev/null 2>&1
  fi
fi

BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && exit 0

MSG="Branch: $BRANCH"

RECENT=$(git -C "$DIR" log --oneline -5 2>/dev/null)
[ -n "$RECENT" ] && MSG="$MSG
Recent commits:
$RECENT"

STATUS=$(git -C "$DIR" status --short 2>/dev/null)
[ -n "$STATUS" ] && MSG="$MSG
Uncommitted changes:
$STATUS"

PRS=$(cd "$DIR" && timeout 5 gh pr list --json number,title --limit 5 2>/dev/null | jq -r '.[] | "#\(.number) \(.title)"' 2>/dev/null)
[ -n "$PRS" ] && MSG="$MSG
Open PRs:
$PRS"

jq -n --arg msg "$MSG" '{"systemMessage": $msg}'
