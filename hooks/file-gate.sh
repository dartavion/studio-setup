#!/bin/bash
# PreToolUse — prompts before new file creation; blocks if declined

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Only gate new files — rewrites of existing files pass through
[ -f "$FILE_PATH" ] && exit 0

# Fail open if not running in an interactive terminal
[ ! -c /dev/tty ] && exit 0

printf '\n  create  %s\n  allow? [enter / n]  ' "$FILE_PATH" >&2
read -n1 -r choice < /dev/tty
printf '\n' >&2

if [[ "$choice" == "n" || "$choice" == "N" ]]; then
  jq -n --arg path "$FILE_PATH" \
    '{"decision":"block","reason":("User declined creation of " + $path)}'
fi
