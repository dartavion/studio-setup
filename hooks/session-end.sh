#!/bin/bash
# Called with "stop" (per-turn) or "end" (session close).
# Per-model API list rates live in pricing.json (same dir). Cost is computed
# per-model from each assistant message's .message.model, so mixed-model
# sessions (e.g. Opus main loop + Haiku subagents) are priced correctly.
#
# Reads the whole transcript on every call (a single jq pass — ~40ms even on a
# 5MB transcript). The earlier delta/temp-file accumulation was dropped: it was
# the source of past double-counting bugs and the perf saving was negligible.

MODE="${1:-end}"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICING="$HOOK_DIR/pricing.json"
# Live cost of in-progress sessions. `stop` overwrites one file per session;
# `end` deletes it after writing the historical log. today-cost.sh unions the
# log with these so the HUD reflects the active session, not just finished ones.
LIVE_DIR="$HOME/.claude/live-cost"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$SESSION_ID" ] && exit 0
[ -f "$PRICING" ] || {
  printf '  session-end: pricing.json not found in %s — cost tracking disabled\n' "$HOOK_DIR" >&2
  exit 0
}

fmt_num() {
  echo "$1" | awk '{n=$1; r=""; while(n>999){r=sprintf(",%03d%s",n%1000,r); n=int(n/1000)}; print n r}'
}
fmt_usd() { awk -v v="$1" 'BEGIN { printf "$%.4f", v }'; }

find_transcript() {
  [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && { echo "$TRANSCRIPT_PATH"; return; }
  find "$HOME/.claude/projects" -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1
}

TPATH=$(find_transcript)
{ [ -z "$TPATH" ] || [ ! -f "$TPATH" ]; } && exit 0

# Single jq pass: group assistant-message usage by model, price each model from
# pricing.json (substring match on the model id), and emit grand totals plus a
# per-model breakdown as one compact JSON object.
STATS=$(jq -s --slurpfile p "$PRICING" '
  def rate($m):
    ($p[0].models) as $r
    | ($m | ascii_downcase) as $lm
    | if   ($lm | test("opus"))   then $r.opus
      elif ($lm | test("sonnet")) then $r.sonnet
      elif ($lm | test("haiku"))  then $r.haiku
      else {input:0, output:0, cache_read:0, cache_write_5m:0, cache_write_1h:0} end;
  [ .[] | select(.type=="assistant" and .message.usage != null) ]
  # Streaming/resume writes the same assistant message as several JSONL lines,
  # each repeating the same message.id and usage. Collapse to one record per
  # message (most-complete wins) so usage is not counted 2-3x. Lines lacking a
  # message.id fall back to their own per-line uuid so they stay distinct.
  | group_by(.message.id // .uuid)
  | map(max_by(.message.usage.output_tokens // 0))
  | map({ model:          (.message.model // "unknown"),
          input:          (.message.usage.input_tokens // 0),
          output:         (.message.usage.output_tokens // 0),
          cache_read:     (.message.usage.cache_read_input_tokens // 0),
          cache_write_5m: (.message.usage.cache_creation.ephemeral_5m_input_tokens // 0),
          cache_write_1h: (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0) })
  | group_by(.model)
  | map( .[0].model as $m | rate($m) as $r
         | { model:          $m,
             input:          (map(.input)|add),
             output:         (map(.output)|add),
             cache_read:     (map(.cache_read)|add),
             cache_write_5m: (map(.cache_write_5m)|add),
             cache_write_1h: (map(.cache_write_1h)|add) }
         | .cost = ( (.input*$r.input + .output*$r.output + .cache_read*$r.cache_read
                      + .cache_write_5m*$r.cache_write_5m + .cache_write_1h*$r.cache_write_1h) / 1000000 ) )
  | { models:         .,
      input:          (map(.input)|add // 0),
      output:         (map(.output)|add // 0),
      cache_read:     (map(.cache_read)|add // 0),
      cache_write_5m: (map(.cache_write_5m)|add // 0),
      cache_write_1h: (map(.cache_write_1h)|add // 0),
      cost:           (map(.cost)|add // 0) }
' "$TPATH" 2>/dev/null)

[ -z "$STATS" ] && exit 0

read -r IN OUT CR CW5 CW1 COST < <(
  echo "$STATS" | jq -r '"\(.input) \(.output) \(.cache_read) \(.cache_write_5m) \(.cache_write_1h) \(.cost)"'
)
CW=$((CW5 + CW1))

if [ "$MODE" = "stop" ]; then
  # Persist the current cumulative cost so the HUD can see this live session.
  mkdir -p "$LIVE_DIR"
  jq -cn --arg sid "$SESSION_ID" --arg ended "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson cost "$COST" \
    '{session_id:$sid, ended_at:$ended, cost_usd:$cost}' > "$LIVE_DIR/${SESSION_ID}.json" 2>/dev/null

  printf '▸ tokens  in=%-9s out=%-8s cr=%-10s cw=%-10s  ~%s\n' \
    "$(fmt_num "$IN")" "$(fmt_num "$OUT")" "$(fmt_num "$CR")" "$(fmt_num "$CW")" "$(fmt_usd "$COST")" >&2

elif [ "$MODE" = "end" ]; then
  PROJECT=$(basename "${CWD:-$(pwd)}")
  BRANCH=$(git -C "${CWD:-.}" branch --show-current 2>/dev/null)

  printf '\n━━ session end ━━━━━━━━━━━━━━━━━━━━━━━━━\n' >&2
  printf '  %-10s %s\n'   "project"  "$PROJECT${BRANCH:+ ($BRANCH)}" >&2
  printf '  %-10s %13s\n' "input"    "$(fmt_num "$IN")"  >&2
  printf '  %-10s %13s\n' "output"   "$(fmt_num "$OUT")" >&2
  printf '  %-10s %13s\n' "cache rd" "$(fmt_num "$CR")"  >&2
  printf '  %-10s %13s\n' "cache wr" "$(fmt_num "$CW")"  >&2
  printf '  ───────────────────────────────────────\n' >&2
  # Per-model cost breakdown (only when more than one model was used).
  if [ "$(echo "$STATS" | jq '.models | length')" -gt 1 ]; then
    echo "$STATS" | jq -r '.models[] | [.model, .cost] | @tsv' | while IFS=$'\t' read -r m c; do
      printf '  %-22s %s\n' "$m" "$(fmt_usd "$c")" >&2
    done
    printf '  ───────────────────────────────────────\n' >&2
  fi
  printf '  %-10s %13s\n' "est. cost" "$(fmt_usd "$COST")" >&2
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' >&2
  printf '  per-model API list rates (not seat cost)\n' >&2

  LOG_FILE="$HOME/.claude/token-log.jsonl"
  jq -cn \
    --argjson in "$IN" --argjson out "$OUT" --argjson cr "$CR" \
    --argjson cw5 "$CW5" --argjson cw1 "$CW1" \
    --arg sid    "$SESSION_ID" \
    --arg proj   "$PROJECT" \
    --arg branch "${BRANCH:-}" \
    --arg ended  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson cost "$COST" \
    --argjson models "$(echo "$STATS" | jq -c '.models')" \
    '{input:$in, output:$out, cache_read:$cr, cache_write_5m:$cw5, cache_write_1h:$cw1,
      session_id:$sid, project:$proj, branch:$branch, ended_at:$ended,
      cost_usd:$cost, models:$models}' \
    >> "$LOG_FILE" 2>/dev/null

  # Session is now in the historical log — drop its live sidecar.
  rm -f "$LIVE_DIR/${SESSION_ID}.json"
fi
