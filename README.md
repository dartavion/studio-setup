# studio-setup

Dev environment kit for designers, engineers, and AI builders.

## What's inside

| Folder | Contents |
|--------|----------|
| `wezterm/` | Terminal config, keybindings, and workspace definitions |
| `vault/` | Obsidian base vault — theme, plugins, dashboard, templates |
| `dotfiles/` | Shell, prompt, and editor config |
| `hooks/` | Claude Code hooks |

---

## Quick start

```bash
git clone git@github.com:dartavion/studio-setup.git
cd studio-setup

# 1. Install WezTerm config and dotfiles
./install.sh

# 2. Download Obsidian plugin binaries and theme
./install.sh --plugins

# 3. Open vault/ in Obsidian — trust the plugins when prompted
```

---

## WezTerm

The base config lives in `wezterm/wezterm.lua` and is symlinked to `~/.config/wezterm/` by `install.sh`.

**What you get:**
- Tokyo Night color scheme, JetBrains Mono Nerd Font
- Vim-style pane navigation (`CMD+SHIFT+h/j/k/l`)
- Pane splits (`CMD+D` horizontal, `CMD+SHIFT+D` vertical)
- Workspace picker (`CMD+O`)
- Status bar showing active workspace, tab titles showing current directory

### Adding a project workspace

Copy the template and fill in your project path:

```bash
cp wezterm/workspaces/workspace.template.lua wezterm/workspaces/my_project.lua
```

Then in `wezterm.lua`, add a require and a key binding:

```lua
local my_project = require 'workspaces.my_project'

-- in config.keys:
{ key = '1', mods = 'CMD', action = my_project.switch_action() },

-- in gui-startup:
my_project.create()
```

Local-only workspaces (not shared in the repo) go directly in `~/.config/wezterm/workspaces/` — `install.sh` won't touch them.

---

## Obsidian

The base vault lives in `vault/`. Open that folder in Obsidian to get the full setup.

**Plugins included:**

| Plugin | Purpose |
|--------|---------|
| Dataview | Powers dashboard queries |
| Templater | Auto-applies templates on note creation |
| Periodic Notes | Daily and weekly notes wired to templates |
| Calendar | Calendar pane + daily note navigation |
| Homepage | Opens Dashboard on vault load |
| Kanban | Project boards |
| QuickAdd | Fast note capture |
| Style Settings | Visual theme tuning |
| Excalidraw | Diagrams and wireframes inside notes |
| Smart Connections | Semantic search and AI chat over your vault |
| Iconize | Per-folder and per-file icons |
| Code Block Customizer | Line numbers, copy button, syntax themes for code blocks |

**Folder structure:**

```
vault/
├── 00-Meta/Templates/   ← Daily, Weekly, Project, Resource templates
├── 01-Periodics/        ← Daily and weekly notes
├── 02-Notes/            ← Reference notes and AI logs
├── 03-Projects/         ← Project notes (status: active / blocked / shipped)
├── 04-Resources/        ← Books, links, courses
├── 09-Review/           ← Inbox and triage
├── reports/             ← KPI snapshots (kpi-snapshot.json)
└── Dashboard.md         ← Homepage with KPIs, tasks, projects, recent notes
```

### KPI dashboard

The dashboard reads `reports/kpi-snapshot.json` and renders KPI cards for PostHog, Grafana, and BigQuery. Replace the placeholder data with output from your own data pipeline:

```bash
# Your sync script writes to:
vault/reports/kpi-snapshot.json
```

The JSON shape:

```json
{
  "updated_at": "2026-06-08T00:00:00Z",
  "window": "2026-05-25 – 2026-06-08",
  "posthog": { "active_users": 0, "active_users_delta": 0, ... },
  "grafana":  { "api_p95_ms": 0, "error_rate_pct": 0, ... },
  "bigquery": { "conversions": 0, "revenue_usd": 0, ... }
}
```

### Per-project vault override

Seed a new project vault from the base without overwriting any existing files:

```bash
./install.sh --vault ~/Developer/my-project/vault
./install.sh --plugins ~/Developer/my-project/vault
```

Then open `my-project/vault/` in Obsidian and customise freely — add CSS snippets, edit the dashboard, change templates. The base vault in this repo is never affected.

---

## Dotfiles

Coming soon.

---

## Claude Code hooks

Coming soon.

---

## Windows

Use `install.ps1` in place of `install.sh`. Hooks use `"shell": "powershell"` in the Claude Code settings entry.
