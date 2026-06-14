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

## Quick start

Clone and run the full install (recommended):

```text
git clone git@github.com:dartavion/studio-setup.git  # SSH (recommended)
# or: git clone https://github.com/dartavion/studio-setup.git
cd studio-setup
./install.sh --full              # macOS / WSL
.\install.ps1 -Full              # Windows PowerShell
```

Prerequisites: Homebrew on macOS (installed automatically if missing) and `gh auth login` run once.


---

### Engineers and AI builders — full setup

```text
git clone git@github.com:dartavion/studio-setup.git  # SSH (recommended)
# or: git clone https://github.com/dartavion/studio-setup.git
cd studio-setup
./install.sh --full              # macOS or WSL (WSL auto-detected, uses apt)
.\install.ps1 -Full              # Windows PowerShell
```

Installs and wires everything: WezTerm, Obsidian, shell config, Neovim, Claude Code hooks, and all Obsidian plugins. Same prerequisites as Quick start above (Homebrew on macOS, `gh auth login` once).

> **`--full` supports macOS and WSL only.** It detects WSL (apt) and otherwise assumes macOS (Homebrew); a native (non-WSL) Linux desktop is not a supported `--full` target and will hit the Homebrew path. On native Linux, use `./install.sh --vault-only` (works anywhere) and install the dev toolchain with your package manager.

**One manual step after full install:** open Obsidian → Add Vault → select `vault/` → Community plugins → click **Trust**. This is an Obsidian security requirement that can't be scripted.

See the [Windows](#windows) section for WSL vs PowerShell details.

---

### Vault-only (minimal)

If you only want the Obsidian vault and plugins without the full developer toolchain, run the vault-only path:

```text
git clone https://github.com/dartavion/studio-setup.git
cd studio-setup
./install.sh --vault-only        # macOS / Linux / WSL
.\install.ps1 -VaultOnly         # Windows PowerShell
```

Or download the ZIP from GitHub, unzip, and run the same command. The script downloads pinned plugin releases and verifies checksums for main plugin binaries.

After install:

1. Open Obsidian → Add Vault → select the `vault/` folder
2. Settings → Community plugins → click "Trust" for each plugin

The Dashboard opens automatically.

---

## WezTerm

Base config is symlinked from `wezterm/wezterm.lua` to `~/.config/wezterm/` by `install.sh`.

**What you get:**
- Ocean Dark (Gogh) color scheme with a Tokyo Night status bar, JetBrains Mono Nerd Font
- [tabline.wez](https://github.com/michaelbrusegard/tabline.wez) status bar — mode, workspace, per-tab cwd/process, RAM/CPU, clock, and **today's Claude Code spend** (read from `~/.claude/token-log.jsonl`; macOS/Linux only)
- Vim-style pane navigation (`CMD+SHIFT+h/j/k/l`)
- Pane splits (`CMD+D` horizontal, `CMD+SHIFT+D` vertical)
- Workspace picker (`CMD+O`)

**Plugins** are fetched from GitHub on first launch and pinned at first clone — they never auto-update. `CMD+a` is the leader (tmux-style prefix), so plugin actions never shadow shell control keys:

| Plugin | What it adds |
|--------|--------------|
| [tabline.wez](https://github.com/michaelbrusegard/tabline.wez) | Status bar + tab line |
| [resurrect](https://github.com/MLFlexer/resurrect.wezterm) | Save/restore window + pane layout — `CMD+a` `w` saves, `CMD+a` `r` restores (auto-saves every 15 min) |
| [smart_ssh](https://github.com/DavidRR-F/smart_ssh.wezterm) | SSH host picker from `~/.ssh/config` — `CMD+a` `Shift+s` (tab), `CMD+a` `5` (hsplit), `CMD+a` `'` (vsplit) |

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
```

Plugins are downloaded automatically as part of `--vault`. Open `my-project/vault/` in Obsidian and customise freely. The base vault is never affected.

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

### Opinionated AI posture

`install.sh` appends an **Epistemic Honesty** section to `~/.claude/CLAUDE.md` — the global instruction file Claude Code reads at the start of every session, across every project.

This is intentionally opinionated. The default failure mode of LLMs is not incompetence — it's approval-seeking: agreeing when they should push back, elaborating when they should ask what the actual problem is, performing confidence when they should surface uncertainty. Left unchecked, this compounds over a long session into a model that tells you what you want to hear.

The section installed here addresses that directly:

- Default to pushback over agreement — disagreement stated plainly is the useful contribution
- State what changed your mind when updating a position; state why you're holding it under pushback
- Don't close loops on raw material — flag gaps instead of papering over them
- Watch for sycophancy drift mid-response and name it when caught

The same content lives in `vault/CLAUDE.md` for vault-scoped sessions and in `dotfiles/claude-global.md` as the single source of truth. Edit that file to update both.

This posture works best with capable models. On weaker models it slows drift without stopping it — the form of the behavior appears without the substance. On models with enough headroom, it consistently produces more honest, more useful engagement.

---

## Windows

There are two supported paths on Windows — choose one or run both.

### Option A: WSL (recommended for engineers)

WSL gives you the full Linux toolchain (zsh, eza, bat, starship, Neovim) with WezTerm and Obsidian running natively on the Windows side.

**Prerequisites:** [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) with Ubuntu, [WezTerm for Windows](https://wezfurlong.org/wezterm/), [Obsidian for Windows](https://obsidian.md).

```bash
# Inside your WSL Ubuntu terminal:
git clone git@github.com:dartavion/studio-setup.git
cd studio-setup
./install.sh --full
```

The script detects WSL automatically and switches to `apt` + curl installers instead of Homebrew. WezTerm and Obsidian are skipped (they run on the Windows side). Open a WezTerm tab pointing at your WSL distro to get the full shell experience.

**`batcat` / `fdfind`:** Ubuntu packages these utilities under different names. The zshrc handles this automatically — `cat` and `fd` work as expected.

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
- Neovim, tree-sitter (CLI), gcc (C compiler for parser builds), starship, eza, bat, fzf, fd, zoxide, JetBrainsMono NF via Scoop
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

Plugin versions are pinned in `versions.lock` and SHA256 checksums are stored in `checksums.sha256`. On every install, each downloaded `main.js` is verified against its stored checksum — a mismatch aborts the install with a clear error. `manifest.json` and `styles.css` are downloaded at the pinned version but are not checksum-verified; `manifest.json` is inert metadata and `styles.css` is display-only.

The npm install for Claude Code uses `--ignore-scripts` to block malicious postinstall hooks on that package.

### Pre-commit hooks and CI secret scanning

This repository includes a pre-commit configuration to run detect-secrets and basic hygiene hooks locally, and a GitHub Action that scans pushes and pull requests for potential secrets. To opt in locally:

```bash
pip install pre-commit
pre-commit install
# optional: run all checks now
pre-commit run --all-files
```

### Generate a .secrets.baseline (recommended)

If detect-secrets reports false positives you want to accept, generate and audit a baseline locally, review it, then commit the baseline so CI accepts the intentional exceptions:

```bash
# Install detect-secrets (user install recommended)
python3 -m pip install --user detect-secrets
# Create a baseline of current findings
detect-secrets scan -o .secrets.baseline
# Interactively audit findings and remove false positives
detect-secrets audit .secrets.baseline
# Review the file, then commit it when ready
git add .secrets.baseline
git commit -m "chore: add .secrets.baseline (false positives acknowledged)"
```

Review SECURITY.md for more details and guidance on handling findings.

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

`install.sh` puts all dotfiles into place (symlinked, except starship — see the table below) and backs up any existing files it would overwrite (e.g. `~/.zshrc.bak.20260608120000`).

| File | Installed to | How |
|------|-------------|-----|
| `dotfiles/zshrc` | `~/.zshrc` | symlink |
| `dotfiles/starship.toml` | `~/.config/starship.toml` | `tokyo-night` preset generated when starship is present; repo file symlinked as fallback |
| `dotfiles/nvim/init.lua` | `~/.config/nvim/init.lua` | symlink |

`dotfiles/zshrc.local.template` is copied to `~/.zshrc.local` on first install (never overwritten after that). Put machine-specific env vars, secrets, and PATH additions there — it is never committed.

### What's configured

**Shell (`zshrc`)**
- No framework — zsh with completion (`compinit`), history, and emacs keybindings configured directly
- `zsh-autosuggestions` and `zsh-syntax-highlighting` (installed via brew/apt, sourced directly)
- `eza` (better `ls`), `bat` (better `cat`), `zoxide` (better `cd`), `fzf`
- NVM, pyenv, pnpm wired up via `$HOME` paths (no hardcoded usernames)
- Starship prompt (initialized last)

**Prompt (`starship.toml`)**
- `install.sh` generates the `tokyo-night` starship preset on install (when starship is present). If preset generation fails or starship isn't installed yet, it falls back to the repo's `dotfiles/starship.toml` (a custom segmented theme). An existing `~/.config/starship.toml` is never overwritten.
- Shows: directory, git branch + status, Node/Python/Go/Rust versions when in-project, command duration, time

**Editor (`nvim/init.lua`)**
- [lazy.nvim](https://github.com/folke/lazy.nvim) plugin manager, auto-installs on first launch
- Catppuccin Mocha colorscheme
- [mason.nvim](https://github.com/williamboman/mason.nvim) — auto-installs LSP servers (TS, Python, Go, Rust, CSS, HTML, JSON, YAML)
- Telescope fuzzy finder (`<leader>ff/fg/fb/fr`)
- nvim-tree file explorer (`<leader>e`)
- [smart-splits](https://github.com/mrjones2014/smart-splits.nvim) — `<C-h/j/k/l>` navigates nvim splits *and* WezTerm panes seamlessly; `<M-h/j/k/l>` resizes
- [lazydev](https://github.com/folke/lazydev.nvim) + wezterm-types — autocomplete and inline docs when editing `wezterm.lua`
- Treesitter highlighting (incl. Kotlin) via nvim-treesitter's `main` branch — required for Neovim 0.12+; parsers are compiled with the `tree-sitter` CLI plus a C compiler, both installed by the kit (gcc via Scoop on Windows, build-essential on WSL, Xcode CLT/clang on macOS)
- blink.cmp autocompletion, conform.nvim format-on-save
- Gitsigns, Neogit (`<leader>gg`), which-key, indent guides, markdown preview

### Machine-specific config

Copy the template and fill in what applies:

```bash
cp dotfiles/zshrc.local.template ~/.zshrc.local
```

Typical entries: `GOOGLE_CLOUD_PROJECT`, API keys, corporate proxy, Android SDK path. See the template for a full reference.
