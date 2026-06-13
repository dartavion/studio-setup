#!/bin/bash

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR="${CWD:-.}"

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
