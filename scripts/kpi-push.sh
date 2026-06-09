#!/usr/bin/env bash
# KPI pipeline template — fetch metrics and write to vault/reports/kpi-snapshot.json.
#
# Run this on a schedule (cron, GitHub Actions, your data server) to keep
# the dashboard current. The vault reads the JSON on every refresh.
#
# Required env vars (put in CI secrets or ~/.zshrc.local):
#   POSTHOG_API_KEY      — PostHog personal API key
#   POSTHOG_PROJECT_ID   — PostHog project ID
#   GRAFANA_URL          — e.g. https://grafana.example.com
#   GRAFANA_API_KEY      — Grafana service account token
#   BIGQUERY_PROJECT     — GCP project ID (uses application default credentials)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$REPO_DIR/vault/reports/kpi-snapshot.json"

WINDOW_DAYS=14
END_DATE=$(date -u +%Y-%m-%d)
# macOS: date -v-14d; Linux: date -d "14 days ago"
START_DATE=$(date -u -v-${WINDOW_DAYS}d +%Y-%m-%d 2>/dev/null \
          || date -u -d "${WINDOW_DAYS} days ago" +%Y-%m-%d)

echo "==> Fetching KPIs for $START_DATE – $END_DATE"

# ── PostHog ───────────────────────────────────────────────────────────────────
# Replace the insight IDs with your own from PostHog → Insights → share link

posthog_query() {
  local insight_id="$1"
  curl -fsSL \
    -H "Authorization: Bearer $POSTHOG_API_KEY" \
    "https://app.posthog.com/api/projects/$POSTHOG_PROJECT_ID/insights/$insight_id/?refresh=true"
}

# Example: pull active users, signups, sessions from your PostHog insights.
# Adapt the .result path for your query type (trends, funnels, etc.)
PH_ACTIVE_USERS=0
PH_ACTIVE_USERS_DELTA=0
PH_NEW_SIGNUPS=0
PH_NEW_SIGNUPS_DELTA=0
PH_SESSIONS=0
PH_SESSIONS_DELTA=0
PH_TOP_EVENT="checkout_started"

# Uncomment and adapt once you have insight IDs:
# PH=$(posthog_query "YOUR_INSIGHT_ID")
# PH_ACTIVE_USERS=$(echo "$PH" | jq '.result[0].aggregated_value')

# ── Grafana ───────────────────────────────────────────────────────────────────
# Use Grafana's HTTP API to query datasource metrics directly.
# https://grafana.com/docs/grafana/latest/developers/http_api/data_source/

grafana_query() {
  local datasource_uid="$1"
  local promql="$2"
  curl -fsSL \
    -H "Authorization: Bearer $GRAFANA_API_KEY" \
    -H "Content-Type: application/json" \
    "$GRAFANA_URL/api/datasources/proxy/uid/$datasource_uid/api/v1/query" \
    --data-urlencode "query=$promql" \
    --data-urlencode "time=$(date -u +%s)"
}

GF_P95=0
GF_P95_DELTA=0
GF_ERROR_RATE=0
GF_ERROR_RATE_DELTA=0
GF_UPTIME=99.99
GF_DEPLOYS=0

# Uncomment and adapt:
# P95_RAW=$(grafana_query "YOUR_DS_UID" 'histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[14d]))')
# GF_P95=$(echo "$P95_RAW" | jq -r '.data.result[0].value[1] | tonumber * 1000 | round')

# ── BigQuery ──────────────────────────────────────────────────────────────────
# Requires gcloud CLI authenticated with application default credentials.
# https://cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query

bq_query() {
  local sql="$1"
  local body
  body=$(jq -n --arg q "$sql" '{query: $q, useLegacySql: false, maxResults: 1}')
  curl -fsSL \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    "https://bigquery.googleapis.com/bigquery/v2/projects/$BIGQUERY_PROJECT/queries" \
    -d "$body"
}

BQ_CONVERSIONS=0
BQ_CONVERSIONS_DELTA=0
BQ_CONV_RATE=0.0
BQ_CONV_RATE_DELTA=0.0
BQ_REVENUE=0
BQ_REVENUE_DELTA=0
BQ_PIPELINE_RUNS=0

# Uncomment and adapt:
# CONV_RAW=$(bq_query "SELECT COUNT(*) as n FROM \`$BIGQUERY_PROJECT.analytics.conversions\` WHERE DATE(created_at) BETWEEN '$START_DATE' AND '$END_DATE'")
# BQ_CONVERSIONS=$(echo "$CONV_RAW" | jq -r '.rows[0].f[0].v | tonumber')

# ── Write snapshot ────────────────────────────────────────────────────────────

cat > "$OUTPUT" <<JSON
{
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "window": "$START_DATE – $END_DATE",
  "posthog": {
    "active_users":       $PH_ACTIVE_USERS,
    "active_users_delta": $PH_ACTIVE_USERS_DELTA,
    "new_signups":        $PH_NEW_SIGNUPS,
    "new_signups_delta":  $PH_NEW_SIGNUPS_DELTA,
    "sessions":           $PH_SESSIONS,
    "sessions_delta":     $PH_SESSIONS_DELTA,
    "top_event":          "$PH_TOP_EVENT"
  },
  "grafana": {
    "api_p95_ms":        $GF_P95,
    "api_p95_delta":     $GF_P95_DELTA,
    "error_rate_pct":    $GF_ERROR_RATE,
    "error_rate_delta":  $GF_ERROR_RATE_DELTA,
    "uptime_pct":        $GF_UPTIME,
    "deploys":           $GF_DEPLOYS
  },
  "bigquery": {
    "conversions":            $BQ_CONVERSIONS,
    "conversions_delta":      $BQ_CONVERSIONS_DELTA,
    "conversion_rate_pct":    $BQ_CONV_RATE,
    "conversion_rate_delta":  $BQ_CONV_RATE_DELTA,
    "revenue_usd":            $BQ_REVENUE,
    "revenue_delta":          $BQ_REVENUE_DELTA,
    "pipeline_runs":          $BQ_PIPELINE_RUNS
  }
}
JSON

echo "==> Written to $OUTPUT"
