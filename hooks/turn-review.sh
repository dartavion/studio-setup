#!/bin/bash
# Stop hook — shows per-turn file receipt and prompts to open changed files in Neovim

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$SESSION_ID" ] && exit 0

EDIT_LIST="/tmp/claude-edits-${SESSION_ID}.txt"
[ ! -f "$EDIT_LIST" ] && exit 0

# Collect files that still exist (edit-tracker already deduplicates)
FILES=()
while IFS= read -r f; do
  [[ -f "$f" ]] && FILES+=("$f")
done < "$EDIT_LIST"

rm -f "$EDIT_LIST"
[[ ${#FILES[@]} -eq 0 ]] && exit 0

# Show relative paths when possible
rel() { local f="$1"; [[ -n "$CWD" ]] && f="${f#${CWD}/}"; echo "$f"; }

printf '\n━━ turn review ━━━━━━━━━━━━━━━━━━━━━━━━\n' >&2
for f in "${FILES[@]}"; do
  printf '  %s\n' "$(rel "$f")" >&2
done
printf '────────────────────────────────────────\n' >&2
[[ ${#FILES[@]} -gt 1 ]] && printf '  nvim: :bn / :bp  navigate  |  :bd  close buffer\n' >&2

# Require interactive terminal
[[ ! -c /dev/tty ]] && exit 0

printf '  open in nvim? [enter / n]  ' >&2
read -n1 -r choice < /dev/tty
printf '\n' >&2
[[ "$choice" == "n" || "$choice" == "N" ]] && exit 0

SOCK="/tmp/nvim-claude.sock"
PANE_ID_FILE="/tmp/nvim-claude-pane-id"

pane_alive() {
  wezterm cli list --format json 2>/dev/null \
    | jq -e --argjson id "$1" '.[] | select(.pane_id == $id)' > /dev/null 2>&1
}

if [[ -f "$PANE_ID_FILE" && -S "$SOCK" ]]; then
  PANE_ID=$(cat "$PANE_ID_FILE")
  if pane_alive "$PANE_ID"; then
    # Load in reverse so FILES[0] ends up as the active buffer
    for (( i=${#FILES[@]}-1; i>=0; i-- )); do
      nvim --server "$SOCK" --remote "${FILES[$i]}" 2>/dev/null
    done
    nvim --server "$SOCK" --remote-send "zz" 2>/dev/null
    exit 0
  fi
fi

# Spawn new pane with all files in the arglist
rm -f "$SOCK"
PANE_ID=$(wezterm cli split-pane -- nvim --listen "$SOCK" "${FILES[@]}" 2>/dev/null)
[[ -z "$PANE_ID" ]] && exit 0
echo "$PANE_ID" > "$PANE_ID_FILE"
i=0
until [[ -S "$SOCK" || $i -ge 20 ]]; do sleep 0.1; i=$((i+1)); done
[[ -S "$SOCK" ]] && nvim --server "$SOCK" --remote-send "zz" 2>/dev/null
