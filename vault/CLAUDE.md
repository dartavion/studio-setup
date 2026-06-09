# Vault Guide for Claude

This is a studio-setup vault. Use this file to understand the structure and conventions before reading or writing notes.

## Folder structure

| Folder | Purpose |
|--------|---------|
| `00-Meta/Templates/` | Note templates — never edit directly, copy when creating new note types |
| `01-Periodics/` | Daily notes (`YYYY-MM-DD.md`) and weekly notes (`YYYY-WWW.md`) |
| `02-Notes/` | Reference notes, research, AI session logs |
| `03-Projects/` | One note per project — always include `status` frontmatter |
| `04-Resources/` | Books, articles, courses, links |
| `09-Review/` | Inbox — drop unclassified notes here for later triage |
| `reports/` | Data snapshots — do not edit manually unless updating KPI data |

## Frontmatter conventions

Every note should have frontmatter. Key fields:

```yaml
---
status: active      # active | blocked | shipped — required for 03-Projects notes
tags: [project]     # matches folder type: daily, weekly, project, resource
started: 2026-06-08 # ISO date — required for 03-Projects notes
---
```

The Dashboard queries `03-Projects/` filtered by `status: active` or `status: blocked`. A project note without a `status` field will not appear on the dashboard.

## Creating notes

- **Daily note** — create `01-Periodics/YYYY-MM-DD.md` using the Daily Note template
- **Project** — create `03-Projects/Project Name.md` using the Project template, always set `status: active`
- **Resource** — create `04-Resources/Title.md` using the Resource template
- **Quick note** — drop into `09-Review/` if unsure where it belongs

## KPI snapshot

The dashboard reads `reports/kpi-snapshot.json`. To update with real data, overwrite this file with the following shape:

```json
{
  "updated_at": "YYYY-MM-DDTHH:MM:SSZ",
  "window": "YYYY-MM-DD – YYYY-MM-DD",
  "posthog": {
    "active_users": 0,        "active_users_delta": 0,
    "new_signups": 0,         "new_signups_delta": 0,
    "sessions": 0,            "sessions_delta": 0,
    "top_event": ""
  },
  "grafana": {
    "api_p95_ms": 0,          "api_p95_delta": 0,
    "error_rate_pct": 0,      "error_rate_delta": 0,
    "uptime_pct": 0,
    "deploys": 0
  },
  "bigquery": {
    "conversions": 0,         "conversions_delta": 0,
    "conversion_rate_pct": 0, "conversion_rate_delta": 0,
    "revenue_usd": 0,         "revenue_delta": 0,
    "pipeline_runs": 0
  }
}
```

Delta fields are percentage change vs. the previous window. Positive deltas are green, negative are red — except `api_p95_delta` and `error_rate_delta` where negative (improvement) is green.

## Dashboard

`Dashboard.md` is the homepage. It contains:
1. Quick links callout — links to each folder
2. KPI cards — reads `reports/kpi-snapshot.json` via DataviewJS
3. Open tasks — all incomplete checkboxes across the vault
4. Active projects — `03-Projects/` notes with `status: active` or `blocked`
5. Recent notes — last 8 modified notes
6. Daily notes — last 7 dated notes

Do not edit the DataviewJS blocks unless changing the KPI schema.

## Plugins in use

Dataview and Templater must be enabled for the dashboard and templates to work. All other plugins enhance the experience but are not required for core functionality.
