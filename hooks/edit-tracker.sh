#!/bin/bash
# PostToolUse — silently records each edited file path for per-turn review

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$SESSION_ID" ] || [ -z "$FILE_PATH" ] && exit 0

EDIT_LIST="/tmp/claude-edits-${SESSION_ID}.txt"
grep -qF "$FILE_PATH" "$EDIT_LIST" 2>/dev/null || echo "$FILE_PATH" >> "$EDIT_LIST"
