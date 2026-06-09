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

## Prerequisites

`./install.sh --full` handles all of these automatically on macOS. You only need two things before running it:

- **Homebrew** — [brew.sh](https://brew.sh) (the script installs it if missing)
- **`gh` authenticated** — run `gh auth login` once before setup if you haven't already

Everything else (WezTerm, Obsidian, Claude Code, JetBrains Mono Nerd Font) is installed by the script.

> **Linux / Windows:** install prerequisites manually — see the table below, then run `./install.sh` (Linux) or `./install.ps1` (Windows).
>
> | Tool | Install |
> |------|---------|
> | [WezTerm](https://wezfurlong.org/wezterm/) | `brew install --cask wezterm` |
> | [Obsidian](https://obsidian.md) | `brew install --cask obsidian` |
> | [Claude Code](https://claude.ai/code) | `npm install -g @anthropic-ai/claude-code` |
> | [JetBrains Mono Nerd Font](https://www.nerdfonts.com/) | `brew install --cask font-jetbrains-mono-nerd-font` |
> | `gh` CLI | `brew install gh && gh auth login` |

---

## Quick start

```bash
git clone git@github.com:dartavion/studio-setup.git
cd studio-setup
./install.sh --full
```

That's it. The script installs all prerequisites, wires WezTerm and Claude Code hooks, downloads all Obsidian plugins, and pre-configures Catppuccin Mocha and DataviewJS.

**One manual step:** open Obsidian → Add Vault → select `vault/` → Settings → Community plugins → click **Trust** for each plugin. This is an Obsidian security requirement that can't be scripted.

**Verify it's working:** open `Dashboard.md` — KPI cards, Active Projects table, and Recent Notes should all render immediately.

---

## WezTerm

Base config is symlinked from `wezterm/wezterm.lua` to `~/.config/wezterm/` by `install.sh`.

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

Then in `wezterm.lua`, wire it up:

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

Base vault is in `vault/`. Open that folder in Obsidian.

**Plugins included:**

| Plugin | Purpose |
|--------|---------|
| Dataview | Powers all dashboard queries |
| Templater | Auto-applies templates on note creation |
| Periodic Notes | Daily and weekly notes wired to templates |
| Calendar | Calendar pane + daily note navigation |
| Homepage | Opens Dashboard on vault load |
| Kanban | Project boards |
| QuickAdd | Fast note capture into any folder |
| Style Settings | Visual theme tuning |
| Excalidraw | Diagrams and wireframes inside notes |
| Smart Connections | Semantic search and AI chat over your vault |
| Iconize | Per-folder and per-file icons |
| Code Block Customizer | Line numbers, copy button, syntax themes for code blocks |

**Folder structure:**

```
vault/
├── 00-Meta/Templates/   ← Daily, Weekly, Project, Resource templates
├── 01-Periodics/        ← Daily and weekly notes (YYYY-MM-DD / YYYY-WWW)
├── 02-Notes/            ← Reference notes and AI logs
├── 03-Projects/         ← Project notes — requires status: frontmatter
├── 04-Resources/        ← Books, links, courses
├── 09-Review/           ← Inbox and triage
├── reports/             ← KPI snapshots
├── CLAUDE.md            ← Vault guide for Claude Code
└── Dashboard.md         ← Homepage — KPIs, tasks, projects, recent notes
```

### KPI dashboard

The dashboard reads `reports/kpi-snapshot.json`. Replace the placeholder with output from your data pipeline:

```json
{
  "updated_at": "YYYY-MM-DDTHH:MM:SSZ",
  "window": "YYYY-MM-DD – YYYY-MM-DD",
  "posthog": { "active_users": 0, "active_users_delta": 0, "new_signups": 0, "new_signups_delta": 0, "sessions": 0, "sessions_delta": 0, "top_event": "" },
  "grafana":  { "api_p95_ms": 0, "api_p95_delta": 0, "error_rate_pct": 0, "error_rate_delta": 0, "uptime_pct": 0, "deploys": 0 },
  "bigquery": { "conversions": 0, "conversions_delta": 0, "conversion_rate_pct": 0, "conversion_rate_delta": 0, "revenue_usd": 0, "revenue_delta": 0, "pipeline_runs": 0 }
}
```

Delta fields are percentage change vs. the previous window. Negative deltas on `api_p95` and `error_rate` are shown as green (improvement).

### Per-project vault override

Seed a new project vault from the base:

```bash
./install.sh --vault ~/Developer/my-project/vault
./install.sh --plugins ~/Developer/my-project/vault
```

Open `my-project/vault/` in Obsidian and customise freely. The base vault is never affected.

---

## Claude Code hooks

`install.sh` symlinks all hooks into `~/.claude/hooks/` and merges the required entries into `~/.claude/settings.json`.

| Hook | Trigger | What it does |
|------|---------|-------------|
| `edit-tracker` | PostToolUse (Edit/Write) | Silently records each edited file path per turn |
| `turn-review` | Stop | Shows edited files at end of turn, prompts to open in Neovim |
| `file-gate` | PreToolUse (Write) | Prompts before new file creation, blocks if declined |
| `session-start` | SessionStart | Injects git context as a system message before the first turn |
| `session-end` | Stop + SessionEnd | Tracks token usage and cost, appends to `~/.claude/token-log.jsonl` |

### AI + vault

The vault includes `CLAUDE.md` — when Claude Code reads your vault it automatically understands the folder structure, frontmatter conventions, and KPI schema. No explanation needed per session.

---

## Windows

Use `install.ps1` in place of `install.sh`. Hook entries in `~/.claude/settings.json` require `"shell": "powershell"`.

---

## Security

Plugin versions are pinned in `versions.lock` and SHA256 checksums are stored in `checksums.sha256`. On every install, each downloaded `main.js` is verified against its stored checksum — a mismatch aborts the install.

The npm install for Claude Code uses `--ignore-scripts` to block malicious postinstall hooks.

### Updating plugins

```bash
./install.sh --update-lock
```

This fetches the latest release for each plugin, re-downloads binaries, recomputes checksums, and updates both files. Review the diff before committing — you're explicitly approving the new versions.

---

## Dotfiles

Coming soon.
