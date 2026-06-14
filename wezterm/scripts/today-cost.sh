#!/usr/bin/env bash
# today-cost.sh — print today's Claude Code spend from the kit's token log.
# Output e.g.:  $9.51 · 2s   (empty if no data / no sessions today / parse error)
# Consumed by the tabline "claude_spend" component in wezterm.lua.
#
# Two sources, unioned:
#   - token-log.jsonl   : one record per *completed* session (written on SessionEnd)
#   - live-cost/*.json  : one record per *in-progress* session (rewritten each turn)
# Grouping by session_id and taking max_by(ended_at) resolves both duplicate log
# entries and the log↔live overlap: a finished session's log record (ended_at =
# end time) always wins over any stale sidecar (ended_at = last turn), and `end`
# deletes the sidecar anyway, so the active session is counted exactly once.
log="$HOME/.claude/token-log.jsonl"
live_dir="$HOME/.claude/live-cost"
today=$(date +%Y-%m-%d)

read -r c n < <(
  {
    [ -f "$log" ] && jq -R 'fromjson? // empty' "$log" 2>/dev/null
    [ -d "$live_dir" ] && cat "$live_dir"/*.json 2>/dev/null | jq -c '. // empty' 2>/dev/null
  } | jq -s --arg d "$today" -r '
      [ .[] | select((.ended_at // "") | startswith($d)) ]
      | group_by(.session_id)
      | map(max_by(.ended_at))
      | "\(map(.cost_usd // 0) | add // 0) \(length)"' 2>/dev/null
)
[ -z "${n:-}" ] && { printf ''; exit 0; }
[ "${n:-0}" -eq 0 ] && { printf ''; exit 0; }
printf '$%.2f · %ss' "${c:-0}" "${n}"
