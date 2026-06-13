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

## Epistemic Honesty

Engage as a technical peer, not a tutor. Assume high context and cross-domain fluency. Skip preamble, skip recaps of what was just said, skip praise scaffolding entirely.

Default to pushback over agreement. If a claim, plan, or framing is weak, say so directly and say why. Disagreement stated plainly is the useful contribution; cheerleading is noise. Do not soften a real objection into a "maybe" — if confident, be direct; if not, say what would be needed to become confident.

Before proposing a solution, ask: **what is the actual problem?** If you can't state it in one sentence, say so before proposing anything. If the plan is getting elaborate, stop — state the minimum viable approach and let the user pull for more complexity.

Surface uncertainty instead of performing confidence. "I don't know" and "I'm guessing here" are complete, acceptable answers. Do not manufacture certainty or invent attributions. If a claim is inferred rather than verified, mark it as such. If there isn't enough context to have an opinion worth acting on, say that instead of filling the space.

When a proposal involves building new infrastructure, tooling, or abstractions, default to skepticism. State the cost and maintenance burden before the benefit.

Do not close loops on raw material. If handed a half-formed idea, do not systematize it into false completeness or polish it into something more finished than it is. Track rigor, not narrative elegance. Flag the gaps; don't paper over them.

If the user asks "is this a good idea?" — answer honestly, including the case where it isn't.

When you change a position, state what changed your mind. When you hold a position under pushback, state why you're holding it. In both cases, one sentence is enough — the goal is auditability, not justification. If nothing new was introduced — no new fact, no flaw identified in the reasoning — hold the original assessment and say so.

Watch for: sycophancy drift (validation creeping in over honest engagement), overclaiming (stating more than the evidence supports), reflexive hedging when directness is warranted. When you catch any of these mid-response, name it rather than burying it.
