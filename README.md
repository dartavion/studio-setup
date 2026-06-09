# studio-setup

Dev environment kit for designers, engineers, and AI builders.

## What's inside

| Folder | Contents |
|--------|----------|
| `vault/` | Obsidian base vault — theme, plugins, dashboard, templates |
| `wezterm/` | Terminal config, keybindings, and workspace definitions |
| `dotfiles/` | Shell, prompt, and editor config |
| `hooks/` | Claude Code hooks |

---

## Pick your path

**Not sure which to choose?**

- You write code every day → **full setup**. Terminal, editor, AI tooling, and the Obsidian vault — all wired together out of the box.
- You live in Figma, Notion, or slides → **vault-only**. Just the Obsidian workspace: KPI dashboard, project tracking, daily notes. Nothing else touches your machine.
- Somewhere in between → start with vault-only. Run `./install.sh --full` later and it picks up without overwriting anything.

---

### Engineers and AI builders — full setup

```bash
git clone git@github.com:dartavion/studio-setup.git  # SSH (recommended)
# or: git clone https://github.com/dartavion/studio-setup.git
cd studio-setup
./install.sh --full              # macOS
.\install.ps1 -Full              # Windows PowerShell
./install.sh --full              # WSL (auto-detected, uses apt)
```

Installs and wires everything: WezTerm, Obsidian, shell config, Neovim, Claude Code hooks, and all Obsidian plugins. Only prerequisites: Homebrew on macOS (installed automatically if missing) and `gh auth login` run once.

**One manual step after full install:** open Obsidian → Add Vault → select `vault/` → Community plugins → click **Trust**. This is an Obsidian security requirement that can't be scripted.

See the [Windows](#windows) section for WSL vs PowerShell details.

---

### Designers and product folks — just Obsidian

One prerequisite: [Obsidian](https://obsidian.md). No `gh` CLI, no SSH keys, no terminal experience needed.

```bash
# HTTPS — no SSH keys required
git clone https://github.com/dartavion/studio-setup.git
cd studio-setup
./install.sh --vault-only        # macOS / Linux / WSL
.\install.ps1 -VaultOnly         # Windows PowerShell
```

The script downloads all plugins directly from GitHub releases at pinned, verified versions. Then:

1. Open Obsidian → **Add Vault** → select the `vault/` folder
2. Settings → Community plugins → click **Trust** for each plugin

The Dashboard opens automatically. KPI cards, tasks, and project tables render immediately.

---

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

`wezterm/workspaces/example.lua` is a complete, working workspace you can copy directly. It opens nvim on the left and a shell on the right:

```bash
cp wezterm/workspaces/example.lua wezterm/workspaces/my_project.lua
# edit WORKSPACE and ROOT at the top of the file
```

Then wire it in `wezterm.lua`:

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

The dashboard reads `reports/kpi-snapshot.json` — a local file your data pipeline writes. Delta fields are percentage change vs. the previous window; negative deltas on `api_p95` and `error_rate` show as green (improvement).

#### Wiring your pipeline

`scripts/kpi-push.sh` is a ready-to-adapt template. It shows how to query PostHog, Grafana, and BigQuery, then write the snapshot JSON. Uncomment and adapt the sections for your setup:

```bash
# required env vars (add to ~/.zshrc.local or CI secrets):
POSTHOG_API_KEY=...
POSTHOG_PROJECT_ID=...
GRAFANA_URL=https://grafana.example.com
GRAFANA_API_KEY=...
BIGQUERY_PROJECT=my-gcp-project

./scripts/kpi-push.sh
```

**Keeping it fresh — two patterns:**

1. **Scheduled GitHub Actions** (recommended for teams) — add a workflow that runs `kpi-push.sh` on a cron schedule and commits the updated JSON. Team members get fresh data on `git pull`. Example job:

```yaml
- name: Fetch and commit KPIs
  run: |
    ./scripts/kpi-push.sh
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add vault/reports/kpi-snapshot.json
    git diff --cached --quiet || git commit -m "chore: update kpi snapshot $(date +%Y-%m-%d)"
    git push
```

2. **Local cron** — run `kpi-push.sh` on a schedule from your machine, commit and push. Lightweight for solo use.

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

There are two supported paths on Windows — choose one or run both.

### Option A: WSL (recommended for engineers)

WSL gives you the full Linux toolchain (zsh, oh-my-zsh, eza, bat, starship, Neovim) with WezTerm and Obsidian running natively on the Windows side.

**Prerequisites:** [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) with Ubuntu, [WezTerm for Windows](https://wezfurlong.org/wezterm/), [Obsidian for Windows](https://obsidian.md).

```bash
# Inside your WSL Ubuntu terminal:
git clone git@github.com:dartavion/studio-setup.git
cd studio-setup
./install.sh --full
```

The script detects WSL automatically and switches to `apt` + curl installers instead of Homebrew. WezTerm and Obsidian are skipped (they run on the Windows side). Open a WezTerm tab pointing at your WSL distro to get the full shell experience.

**`batcat` / `fdfind`:** Ubuntu packages these utilities under different names. The zshrc handles this automatically — `cat` and `fd` work as expected.

**oh-my-zsh:** Same manual step as macOS — run the curl installer once in a zsh session, then the symlinked `.zshrc` takes over.

### Option B: PowerShell native

Full Windows-native setup using winget (GUI apps) and Scoop (CLI tools).

**Prerequisites:** Windows 10/11 with winget. Run in PowerShell 7 (`pwsh`), not Windows PowerShell 5.

```powershell
git clone git@github.com:dartavion/studio-setup.git
cd studio-setup
.\install.ps1 -Full
```

**What gets installed:**
- WezTerm, Obsidian, Node.js via winget
- Neovim, starship, eza, bat, fzf, fd, zoxide, JetBrainsMono NF via Scoop
- Claude Code via npm (`--ignore-scripts`)
- PSFzf module for fzf key bindings in PowerShell

**Dotfiles wired:**
- `$PROFILE` → `dotfiles/powershell/profile.ps1`
- `~\.config\starship.toml` → `dotfiles/starship.toml`
- `~\AppData\Local\nvim\init.lua` → `dotfiles/nvim/init.lua`
- `profile.local.ps1` seeded from template in the same folder as `$PROFILE`

Uses symlinks where Developer Mode is enabled; falls back to copying otherwise.

### AI on Windows

Claude Code works identically on both paths — same `claude` CLI, same hooks. On the PowerShell path, hooks run as `.ps1` files with `"shell": "powershell"` in `settings.json`. On WSL, hooks run as `.sh` files exactly as on macOS.

`--update-lock` (regenerating plugin checksums) requires Python 3 and is not ported to PowerShell. On a Windows-only machine run it via WSL:

```powershell
wsl ./install.sh --update-lock
```

---

## Security

Plugin versions are pinned in `versions.lock` and SHA256 checksums are stored in `checksums.sha256`. On every install, each downloaded `main.js` is verified against its stored checksum — a mismatch aborts the install with a clear error.

The npm install for Claude Code uses `--ignore-scripts` to block malicious postinstall hooks.

### Keeping plugins updated

**The preferred path is the GitHub Actions workflow**, not `--update-lock` locally. The workflow runs every Monday at 9am UTC and is explicitly two-phase:

1. **Tamper detection first** — re-downloads the currently pinned binaries and compares their SHA256 against `checksums.sha256`. A mismatch means a release binary was silently replaced after it was pinned — a supply chain attack. The job opens a security issue and exits 1, blocking any PR from being opened.
2. **Version check second** — only if tamper detection passes does it look for newer releases and open a PR.

Merging the PR is the explicit human approval step. Team members get updates on next `git pull && ./install.sh --plugins`.

### Running `--update-lock` locally

> **Security notice:** `--update-lock` downloads new plugin binaries and recomputes their checksums from what it just downloaded. This means it inherently trusts the download. If those binaries were tampered with, the new checksums would "verify" the compromised files — and you'd commit the attack into the repo.

When you do need to run it locally:

- **Use a trusted network.** Never run it on public Wi-Fi or an untrusted connection.
- **Review the diff before committing.** Only `versions.lock` and `checksums.sha256` should change. Plugin binaries (`main.js`, `styles.css`) are gitignored and must not be committed.
- **Prefer opening a PR** rather than pushing directly to main, so a second pair of eyes can review.
- **When in doubt, trigger the GitHub Actions workflow instead** — it has the tamper detection step that the local command does not.

```bash
./install.sh --update-lock

# Audit the diff — only these two files should change:
git diff versions.lock checksums.sha256

# Open a PR rather than pushing directly:
git checkout -b chore/update-plugins
git add versions.lock checksums.sha256
git commit -m "chore: update plugin versions $(date +%Y-%m-%d)"
git push -u origin chore/update-plugins
gh pr create
```

Or trigger the workflow directly from the GitHub Actions tab — no local changes needed.

---

## Dotfiles

`install.sh` symlinks all dotfiles into place and backs up any existing files it would overwrite (e.g. `~/.zshrc.bak.20260608120000`).

| File | Symlinked to |
|------|-------------|
| `dotfiles/zshrc` | `~/.zshrc` |
| `dotfiles/starship.toml` | `~/.config/starship.toml` |
| `dotfiles/nvim/init.lua` | `~/.config/nvim/init.lua` |

`dotfiles/zshrc.local.template` is copied to `~/.zshrc.local` on first install (never overwritten after that). Put machine-specific env vars, secrets, and PATH additions there — it is never committed.

### What's configured

**Shell (`zshrc`)**
- oh-my-zsh with `zsh-autosuggestions` and `zsh-syntax-highlighting`
- `eza` (better `ls`), `bat` (better `cat`), `zoxide` (better `cd`), `fzf`
- NVM, pyenv, pnpm wired up via `$HOME` paths (no hardcoded usernames)
- Starship prompt (must be last — overrides oh-my-zsh theme)

**Prompt (`starship.toml`)**
- Catppuccin Mocha palette — matches Neovim and Obsidian
- Shows: directory, git branch + status, Node/Python/Go/Rust versions when in-project, command duration, time

**Editor (`nvim/init.lua`)**
- [lazy.nvim](https://github.com/folke/lazy.nvim) plugin manager, auto-installs on first launch
- Catppuccin Mocha colorscheme
- [mason.nvim](https://github.com/williamboman/mason.nvim) — auto-installs LSP servers (TS, Python, Go, Rust, CSS, HTML, JSON, YAML)
- Telescope fuzzy finder (`<leader>ff/fg/fb/fr`)
- nvim-tree file explorer (`<leader>e`)
- Treesitter highlighting, nvim-cmp autocompletion, conform.nvim format-on-save
- Gitsigns, Neogit (`<leader>gg`), which-key, indent guides, markdown preview

### Machine-specific config

Copy the template and fill in what applies:

```bash
cp dotfiles/zshrc.local.template ~/.zshrc.local
```

Typical entries: `GOOGLE_CLOUD_PROJECT`, API keys, corporate proxy, Android SDK path. See the template for a full reference.

### oh-my-zsh

oh-my-zsh is not installed by `install.sh --full` because it requires an interactive shell prompt during install. Run it once manually:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Then open a new shell — the symlinked `~/.zshrc` takes over.
