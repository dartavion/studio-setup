#!/bin/bash
# Called with "stop" (per-turn) or "end" (session close)
# Rates are read from pricing.json in the same directory — edit that file to switch models.

MODE="${1:-end}"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$SESSION_ID" ] && exit 0

TEMP_FILE="/tmp/claude-tokens-${SESSION_ID}.json"

fmt_num() {
  echo "$1" | awk '{n=$1; r=""; while(n>999){r=sprintf(",%03d%s",n%1000,r); n=int(n/1000)}; print n r}'
}

fmt_usd() {
  awk -v v="$1" 'BEGIN { printf "$%.4f", v }'
}

read -r PRICING_MODEL R_IN R_OUT R_CR R_CW5 R_CW1 < <(python3 -c "
import json
p = json.load(open('$HOOK_DIR/pricing.json'))
r = p['rates_usd_per_mtok']
print(p.get('model','unknown'), r['input'], r['output'], r['cache_read'], r['cache_write_5m'], r['cache_write_1h'])
" 2>/dev/null) || true

if [ -z "$R_IN" ]; then
  printf '  session-end: could not load pricing.json from %s — cost tracking disabled\n' "$HOOK_DIR" >&2
  exit 0
fi

calc_cost() {
  awk -v tok_in="$1" -v tok_out="$2" -v cr="$3" -v cw5="$4" -v cw1="$5" \
      -v r_in="$R_IN" -v r_out="$R_OUT" -v r_cr="$R_CR" -v r_cw5="$R_CW5" -v r_cw1="$R_CW1" '
    BEGIN { printf "%.4f", (tok_in*r_in + tok_out*r_out + cr*r_cr + cw5*r_cw5 + cw1*r_cw1) / 1000000 }
  '
}

# Sum usage from line $2 onward (1-based). Reads only new lines, not the full transcript.
sum_usage_from() {
  local path="$1"
  local from_line="${2:-1}"
  [ -z "$path" ] || [ ! -f "$path" ] && return
  tail -n "+${from_line}" "$path" | jq -s '{
    input:          ([.[] | select(.type=="assistant" and .message.usage!=null) | .message.usage.input_tokens                             // 0] | add // 0),
    output:         ([.[] | select(.type=="assistant" and .message.usage!=null) | .message.usage.output_tokens                           // 0] | add // 0),
    cache_read:     ([.[] | select(.type=="assistant" and .message.usage!=null) | .message.usage.cache_read_input_tokens                  // 0] | add // 0),
    cache_write_5m: ([.[] | select(.type=="assistant" and .message.usage!=null) | .message.usage.cache_creation.ephemeral_5m_input_tokens // 0] | add // 0),
    cache_write_1h: ([.[] | select(.type=="assistant" and .message.usage!=null) | .message.usage.cache_creation.ephemeral_1h_input_tokens // 0] | add // 0)
  }' 2>/dev/null
}

find_transcript() {
  [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && { echo "$TRANSCRIPT_PATH"; return; }
  find "$HOME/.claude/projects" -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1
}

if [ "$MODE" = "stop" ]; then
  TPATH=$(find_transcript)
  [ -z "$TPATH" ] && exit 0

  TOTAL_LINES=$(wc -l < "$TPATH")
  PREV_LINES=0
  PREV_IN=0; PREV_OUT=0; PREV_CR=0; PREV_CW5=0; PREV_CW1=0

  if [ -f "$TEMP_FILE" ]; then
    PREV=$(cat "$TEMP_FILE")
    PREV_LINES=$(echo "$PREV" | jq '.lines_read // 0')
    PREV_IN=$(echo "$PREV"   | jq '.input // 0')
    PREV_OUT=$(echo "$PREV"  | jq '.output // 0')
    PREV_CR=$(echo "$PREV"   | jq '.cache_read // 0')
    PREV_CW5=$(echo "$PREV"  | jq '.cache_write_5m // 0')
    PREV_CW1=$(echo "$PREV"  | jq '.cache_write_1h // 0')
  fi

  if [ "$TOTAL_LINES" -le "$PREV_LINES" ]; then
    IN=$PREV_IN; OUT=$PREV_OUT; CR=$PREV_CR; CW5=$PREV_CW5; CW1=$PREV_CW1
  else
    DELTA=$(sum_usage_from "$TPATH" "$((PREV_LINES + 1))")
    [ -z "$DELTA" ] && exit 0
    D_IN=$(echo "$DELTA"  | jq '.input')
    D_OUT=$(echo "$DELTA" | jq '.output')
    D_CR=$(echo "$DELTA"  | jq '.cache_read')
    D_CW5=$(echo "$DELTA" | jq '.cache_write_5m')
    D_CW1=$(echo "$DELTA" | jq '.cache_write_1h')
    IN=$((PREV_IN + D_IN));   OUT=$((PREV_OUT + D_OUT))
    CR=$((PREV_CR + D_CR));   CW5=$((PREV_CW5 + D_CW5)); CW1=$((PREV_CW1 + D_CW1))
    jq -n \
      --argjson in "$IN" --argjson out "$OUT" --argjson cr "$CR" \
      --argjson cw5 "$CW5" --argjson cw1 "$CW1" --argjson lines "$TOTAL_LINES" \
      '{input:$in, output:$out, cache_read:$cr, cache_write_5m:$cw5, cache_write_1h:$cw1, lines_read:$lines}' \
      > "$TEMP_FILE"
  fi

  COST=$(calc_cost "$IN" "$OUT" "$CR" "$CW5" "$CW1")
  CW=$((CW5 + CW1))
  printf '▸ tokens  in=%-9s out=%-8s cr=%-10s cw=%-10s  ~%s\n' \
    "$(fmt_num "$IN")" "$(fmt_num "$OUT")" "$(fmt_num "$CR")" "$(fmt_num "$CW")" "$(fmt_usd "$COST")" >&2

elif [ "$MODE" = "end" ]; then
  if [ -f "$TEMP_FILE" ]; then
    PREV=$(cat "$TEMP_FILE")
    IN=$(echo "$PREV"  | jq '.input')
    OUT=$(echo "$PREV" | jq '.output')
    CR=$(echo "$PREV"  | jq '.cache_read')
    CW5=$(echo "$PREV" | jq '.cache_write_5m')
    CW1=$(echo "$PREV" | jq '.cache_write_1h')
  else
    TPATH=$(find_transcript)
    USAGE=$(sum_usage_from "$TPATH" 1)
    [ -z "$USAGE" ] && exit 0
    IN=$(echo "$USAGE"  | jq '.input')
    OUT=$(echo "$USAGE" | jq '.output')
    CR=$(echo "$USAGE"  | jq '.cache_read')
    CW5=$(echo "$USAGE" | jq '.cache_write_5m')
    CW1=$(echo "$USAGE" | jq '.cache_write_1h')
  fi

  CW=$((CW5 + CW1))
  COST=$(calc_cost "$IN" "$OUT" "$CR" "$CW5" "$CW1")
  PROJECT=$(basename "${CWD:-$(pwd)}")
  BRANCH=$(git -C "${CWD:-.}" branch --show-current 2>/dev/null)

  printf '\n━━ session end ━━━━━━━━━━━━━━━━━━━━━━━━━\n' >&2
  printf '  %-10s %s\n'    "project"  "$PROJECT${BRANCH:+ ($BRANCH)}" >&2
  printf '  %-10s %13s\n'  "input"    "$(fmt_num "$IN")"    >&2
  printf '  %-10s %13s\n'  "output"   "$(fmt_num "$OUT")"   >&2
  printf '  %-10s %13s\n'  "cache rd" "$(fmt_num "$CR")"    >&2
  printf '  %-10s %13s\n'  "cache wr" "$(fmt_num "$CW")"    >&2
  printf '  ───────────────────────────────────────\n' >&2
  printf '  %-10s %13s\n'  "est. cost" "$(fmt_usd "$COST")" >&2
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' >&2
  printf '  API list rates: %s  (not seat cost)\n' "$PRICING_MODEL" >&2

  LOG_FILE="$HOME/.claude/token-log.jsonl"
  jq -n \
    --argjson in "$IN" --argjson out "$OUT" --argjson cr "$CR" \
    --argjson cw5 "$CW5" --argjson cw1 "$CW1" \
    --arg sid    "$SESSION_ID" \
    --arg proj   "$PROJECT" \
    --arg branch "${BRANCH:-}" \
    --arg ended  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cost   "$COST" \
    '{input:$in, output:$out, cache_read:$cr, cache_write_5m:$cw5, cache_write_1h:$cw1, session_id:$sid, project:$proj, branch:$branch, ended_at:$ended, cost_usd:($cost|tonumber)}' \
    >> "$LOG_FILE" 2>/dev/null

  rm -f "$TEMP_FILE"
fi
