---
cssclasses:
  - dashboard
---

# 🏠 Dashboard

> [!note] Quick Links
> [[03-Projects/|Projects]] · [[01-Periodics/|Periodics]] · [[02-Notes/|Notes]] · [[04-Resources/|Resources]] · [[09-Review/|Review]]

## 📊 KPIs — Last 14 Days
```dataviewjs
const render = async () => {
  dv.container.innerHTML = `
    <div class="kpi-loading">
      <span class="kpi-spinner"></span> Loading KPIs…
    </div>`;

  let k;
  try {
    const raw = await app.vault.adapter.read("reports/kpi-snapshot.json");
    k = JSON.parse(raw);
  } catch (e) {
    dv.container.innerHTML = `
      <div class="kpi-error">
        <strong>KPI data not found or invalid.</strong><br>
        Run <code>scripts/kpi-push.sh</code> to generate it, or update
        <code>reports/kpi-snapshot.json</code> with your pipeline output.
      </div>`;
    return;
  }

  const fmt = n => n?.toLocaleString() ?? "—";
  const pct = n => n != null ? `${n}%` : "—";

  const delta = (d, invert = false) => {
    if (d == null) return "";
    const good = invert ? d < 0 : d > 0;
    const cls = good ? "kpi-up" : d === 0 ? "" : "kpi-down";
    const arrow = d > 0 ? "▲" : "▼";
    return `<span class="${cls}">${arrow} ${Math.abs(d)}%</span>`;
  };

  const card = (label, value, d, invert = false) =>
    `<div class="kpi-card">
      <div class="kpi-label">${label}</div>
      <div class="kpi-value">${value}</div>
      <div class="kpi-delta">${delta(d, invert)}</div>
    </div>`;

  const group = (title, cards) =>
    `<div class="kpi-group">
      <div class="kpi-group-title">${title}</div>
      <div class="kpi-grid">${cards.join("")}</div>
    </div>`;

  const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });

  dv.container.innerHTML = `
    <div class="kpi-dashboard">
      <div class="kpi-header">
        <div class="kpi-meta">Window: ${k.window} · Data: ${k.updated_at.slice(0,10)}</div>
        <div class="kpi-actions">
          <span class="kpi-last-refreshed">Refreshed ${now}</span>
          <button class="kpi-refresh-btn">↻ Refresh</button>
        </div>
      </div>
      ${group("PostHog — Product", [
        card("Active Users",   fmt(k.posthog.active_users),      k.posthog.active_users_delta),
        card("New Signups",    fmt(k.posthog.new_signups),        k.posthog.new_signups_delta),
        card("Sessions",       fmt(k.posthog.sessions),           k.posthog.sessions_delta),
        card("Top Event",      k.posthog.top_event),
      ])}
      ${group("Grafana — Infrastructure", [
        card("API p95",        `${k.grafana.api_p95_ms}ms`,       k.grafana.api_p95_delta,    true),
        card("Error Rate",     pct(k.grafana.error_rate_pct),     k.grafana.error_rate_delta, true),
        card("Uptime",         pct(k.grafana.uptime_pct)),
        card("Deploys",        fmt(k.grafana.deploys)),
      ])}
      ${group("BigQuery — Business", [
        card("Conversions",    fmt(k.bigquery.conversions),       k.bigquery.conversions_delta),
        card("Conv. Rate",     pct(k.bigquery.conversion_rate_pct), k.bigquery.conversion_rate_delta),
        card("Revenue",        `$${fmt(k.bigquery.revenue_usd)}`, k.bigquery.revenue_delta),
        card("Pipeline Runs",  fmt(k.bigquery.pipeline_runs)),
      ])}
    </div>`;

  dv.container.querySelector('.kpi-refresh-btn').addEventListener('click', render);
};

await render();
```

## ✅ Open Tasks
```dataview
TASK
FROM ""
WHERE !completed AND !contains(file.path, "Dashboard")
GROUP BY file.link
SORT file.mtime DESC
```

## 🕐 Recent Notes
```dataview
TABLE WITHOUT ID
  file.link AS "Note",
  file.folder AS "Folder",
  file.mtime AS "Modified"
FROM ""
WHERE file.name != "Dashboard"
SORT file.mtime DESC
LIMIT 8
```

## 📁 Active Projects
```dataview
TABLE WITHOUT ID
  file.link AS "Project",
  status AS "Status",
  started AS "Started"
FROM "03-Projects"
WHERE status = "active" OR status = "blocked"
SORT file.mtime DESC
```

## 📅 Daily Notes
```dataview
TABLE WITHOUT ID
  file.link AS "Day",
  file.mtime AS "Modified"
FROM ""
WHERE file.name =~ "^\d{4}-\d{2}-\d{2}$"
SORT file.name DESC
LIMIT 7
```
