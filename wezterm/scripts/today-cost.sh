#!/usr/bin/env bash
# today-cost.sh — print today's Claude Code spend from the kit's token log.
# Output e.g.:  $9.51 · 2s   (empty if no log / no sessions today / parse error)
# Consumed by the tabline "claude_spend" component in wezterm.lua.
# Resolves duplication and cumulative updates by grouping by session_id and taking the latest.
log="$HOME/.claude/token-log.jsonl"
[ -f "$log" ] || { printf ''; exit 0; }
today=$(date +%Y-%m-%d)
# token-log.jsonl is one compact JSON record per line; fromjson? skips any bad line.
read -r c n < <(
  jq -R 'fromjson? // empty' "$log" 2>/dev/null \
  | jq -s --arg d "$today" -r '
      [ .[] | select((.ended_at // "") | startswith($d)) ]
      | group_by(.session_id)
      | map(max_by(.ended_at))
      | "\(map(.cost_usd // 0) | add // 0) \(length)"' 2>/dev/null
)
[ -z "${n:-}" ] && { printf ''; exit 0; }
[ "${n:-0}" -eq 0 ] && { printf ''; exit 0; }
printf '$%.2f · %ss' "${c:-0}" "${n}"
