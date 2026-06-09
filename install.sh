#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_VAULT="$REPO_DIR/vault"
LOCK_FILE="$REPO_DIR/versions.lock"
CHECKSUM_FILE="$REPO_DIR/checksums.sha256"

usage() {
  echo "Usage:"
  echo "  $0 --vault-only           Obsidian only: download plugins, open vault/ in Obsidian"
  echo "  $0 --full                 Full setup: prerequisites + everything below"
  echo "  $0                        Install WezTerm config and Claude Code hooks"
  echo "  $0 --plugins [vault]      Download plugin binaries into vault (default: vault/)"
  echo "  $0 --vault <path>         Seed a project vault from the base vault"
  echo "  $0 --update-lock          Update versions.lock and checksums.sha256 to latest"
  exit 1
}

# ── Security helpers ──────────────────────────────────────────────────────────

pinned_version() {
  local id="$1"
  python3 -c "import json,sys; d=json.load(open('$LOCK_FILE')); print(d['plugins'].get('$id','latest'))"
}

stored_checksum() {
  local id="$1"
  grep "^$id=" "$CHECKSUM_FILE" 2>/dev/null | cut -d= -f2 || true
}

verify_checksum() {
  local id="$1" file="$2"
  local expected actual
  expected="$(stored_checksum "$id")"
  [ -z "$expected" ] && return 0  # no stored checksum yet — first run
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo ""
    echo "  !! CHECKSUM MISMATCH: $id"
    echo "     expected: $expected"
    echo "     got:      $actual"
    echo "     Aborting. If this is a legitimate update run: $0 --update-lock"
    exit 1
  fi
}

# ── Plugin manifest: id -> github_repo ───────────────────────────────────────

PLUGIN_IDS=(
  "calendar:liamcain/obsidian-calendar-plugin"
  "dataview:blacksmithgu/obsidian-dataview"
  "homepage:mirnovov/obsidian-homepage"
  "obsidian-kanban:mgmeyers/obsidian-kanban"
  "obsidian-style-settings:mgmeyers/obsidian-style-settings"
  "quickadd:chhoumann/quickadd"
  "periodic-notes:liamcain/obsidian-periodic-notes"
  "templater-obsidian:SilentVoid13/Templater"
  "obsidian-excalidraw-plugin:zsviczian/obsidian-excalidraw-plugin"
  "smart-connections:brianpetro/obsidian-smart-connections"
  "obsidian-icon-folder:FlorianWoelki/obsidian-iconize"
  "codeblock-customizer:mugiwara85/CodeblockCustomizer"
)

gh_available() {
  command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1
}

# Download a single release asset.
# Tries the direct GitHub URL first (no auth needed).
# Falls back to gh api for repos with non-standard asset layouts.
download_asset() {
  local repo="$1" version="$2" asset="$3" dest="$4"

  local direct="https://github.com/$repo/releases/download/$version/$asset"
  if curl -fsL "$direct" -o "$dest" 2>/dev/null; then
    return 0
  fi

  if gh_available; then
    local url
    url=$(gh api "repos/$repo/releases/tags/$version" \
      -q ".assets[] | select(.name == \"$asset\") | .browser_download_url" 2>/dev/null || true)
    if [ -z "$url" ]; then
      url=$(gh api "repos/$repo/releases/latest" \
        -q ".assets[] | select(.name == \"$asset\") | .browser_download_url" 2>/dev/null || true)
    fi
    if [ -n "$url" ]; then
      curl -sL "$url" -o "$dest"
      return 0
    fi
  fi

  return 1
}

install_plugins() {
  local target="$1/.obsidian"
  echo "==> Installing plugins into $target"

  for entry in "${PLUGIN_IDS[@]}"; do
    local id="${entry%%:*}" repo="${entry##*:}"
    local version
    version="$(pinned_version "$id")"
    mkdir -p "$target/plugins/$id"
    echo "  $id @ $version"

    for asset in main.js manifest.json styles.css; do
      local dest="$target/plugins/$id/$asset"
      if download_asset "$repo" "$version" "$asset" "$dest"; then
        if [ "$asset" = "main.js" ]; then
          verify_checksum "$id" "$dest"
        fi
      fi
    done
  done

  # Catppuccin theme
  local theme_dir="$target/themes/Catppuccin"
  if [ ! -f "$theme_dir/theme.css" ]; then
    echo "  Catppuccin theme"
    mkdir -p "$theme_dir"
    curl -sL "https://raw.githubusercontent.com/catppuccin/obsidian/main/theme.css"     -o "$theme_dir/theme.css"
    curl -sL "https://raw.githubusercontent.com/catppuccin/obsidian/main/manifest.json"  -o "$theme_dir/manifest.json"
  fi

  echo "==> plugins installed and verified"
}

# ── Update lockfile ───────────────────────────────────────────────────────────

update_lock() {
  echo "==> Updating versions.lock and checksums.sha256"
  echo "    Review all version changes before committing."
  echo ""

  local versions_json='{"plugins":{'
  local first=1
  for entry in "${PLUGIN_IDS[@]}"; do
    local id="${entry%%:*}" repo="${entry##*:}"
    local version
    version=$(gh api "repos/$repo/releases/latest" -q '.tag_name' 2>/dev/null)
    echo "  $id -> $version"
    [ $first -eq 0 ] && versions_json+=","
    versions_json+="\"$id\":\"$version\""
    first=0
  done
  versions_json+="}}"
  echo "$versions_json" | python3 -m json.tool > "$LOCK_FILE"

  # Re-download and recompute checksums
  install_plugins "$BASE_VAULT"

  printf "# SHA256 checksums for plugin main.js files at pinned versions\n" > "$CHECKSUM_FILE"
  printf "# Regenerate with: ./install.sh --update-lock\n\n" >> "$CHECKSUM_FILE"
  for dir in "$BASE_VAULT/.obsidian/plugins/"/*/; do
    local id
    id="$(basename "$dir")"
    [ -f "$dir/main.js" ] && \
      echo "$id=$(shasum -a 256 "$dir/main.js" | awk '{print $1}')" >> "$CHECKSUM_FILE"
  done

  echo ""
  echo "==> Lock updated. Review the diff, then commit versions.lock and checksums.sha256."
}

# ── Detect environment ────────────────────────────────────────────────────────

is_wsl() {
  [ -f /proc/version ] && grep -qi "microsoft" /proc/version
}

# ── Full install ──────────────────────────────────────────────────────────────

full_install() {
  echo "==> studio-setup full install"

  if is_wsl; then
    echo "  detected: WSL"
    full_install_wsl
  else
    full_install_macos
  fi
}

full_install_wsl() {
  echo "  updating apt..."
  sudo apt-get update -qq

  apt_install() {
    local pkg="$1"
    if ! dpkg -s "$pkg" &>/dev/null; then
      echo "  installing $pkg..."
      sudo apt-get install -y "$pkg"
    else
      echo "  $pkg ok"
    fi
  }

  apt_install zsh
  apt_install curl
  apt_install git
  apt_install neovim
  apt_install fzf
  apt_install bat         # installs as batcat on Ubuntu — zshrc handles alias
  apt_install fd-find     # installs as fdfind on Ubuntu — zshrc handles alias
  apt_install ripgrep
  apt_install unzip

  if ! command -v node &>/dev/null; then
    echo "  installing Node.js via nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
  else
    echo "  node ok"
  fi

  if ! command -v gh &>/dev/null; then
    echo "  installing gh CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update -qq && sudo apt-get install -y gh
  else
    echo "  gh ok"
  fi

  if ! command -v starship &>/dev/null; then
    echo "  installing starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
  else
    echo "  starship ok"
  fi

  if ! command -v eza &>/dev/null; then
    echo "  installing eza..."
    curl -sL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
      | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt-get update -qq && sudo apt-get install -y eza
  else
    echo "  eza ok"
  fi

  if ! command -v zoxide &>/dev/null; then
    echo "  installing zoxide..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  else
    echo "  zoxide ok"
  fi

  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo ""
    echo "  WSL note: set zsh as default shell with:"
    echo "    chsh -s \$(which zsh)"
    echo "  Then install oh-my-zsh manually (requires interactive shell):"
    echo '    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    echo ""
  fi

  if ! command -v claude &>/dev/null; then
    echo "  installing Claude Code..."
    npm install -g --ignore-scripts @anthropic-ai/claude-code
  else
    echo "  claude ok"
  fi

  if ! gh auth status &>/dev/null; then
    echo ""
    echo "  gh is not authenticated. Run: gh auth login"
    echo "  Then re-run: $0 --full"
    exit 1
  fi

  bash "$0"
  install_plugins "$BASE_VAULT"

  echo ""
  echo "==> All done (WSL)."
  echo ""
  echo "  Manual steps remaining:"
  echo ""
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "  1. Install oh-my-zsh:"
    echo '     sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    echo ""
  fi
  echo "  Open Obsidian on the Windows side → Add Vault → select vault/"
  echo "  Settings → Community plugins → click 'Trust' for each plugin"
  echo ""
  echo "  Note: WezTerm and Obsidian run on Windows, not inside WSL."
  echo "  From WezTerm, open a WSL tab: New Tab → Ubuntu (or your distro)"
}

full_install_macos() {
  # ── Homebrew ────────────────────────────────────────────────────────────────
  if ! command -v brew &>/dev/null; then
    echo "  installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "  homebrew ok"
  fi

  install_cask() {
    local app="$1" cask="$2"
    if ! brew list --cask "$cask" &>/dev/null; then
      echo "  installing $cask..."
      brew install --cask "$cask"
    else
      echo "  $app ok"
    fi
  }

  install_formula() {
    local formula="$1"
    if ! brew list "$formula" &>/dev/null; then
      echo "  installing $formula..."
      brew install "$formula"
    else
      echo "  $formula ok"
    fi
  }

  install_cask    "WezTerm"           "wezterm"
  install_cask    "Obsidian"          "obsidian"
  install_cask    "JetBrains Mono NF" "font-jetbrains-mono-nerd-font"
  install_formula "gh"
  install_formula "node"
  install_formula "neovim"
  install_formula "starship"
  install_formula "eza"
  install_formula "bat"
  install_formula "fzf"
  install_formula "fd"
  install_formula "zoxide"
  install_formula "zsh-autosuggestions"
  install_formula "zsh-syntax-highlighting"

  if ! command -v claude &>/dev/null; then
    echo "  installing Claude Code..."
    npm install -g --ignore-scripts @anthropic-ai/claude-code
  else
    echo "  claude ok"
  fi

  if ! gh auth status &>/dev/null; then
    echo ""
    echo "  gh is not authenticated. Run: gh auth login"
    echo "  Then re-run: $0 --full"
    exit 1
  fi

  bash "$0"
  install_plugins "$BASE_VAULT"

  echo ""
  echo "==> All done."
  echo ""

  local step=1
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "  Manual steps required:"
    echo ""
    echo "  $step. Install oh-my-zsh (requires an interactive shell — can't be scripted):"
    echo '     sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    echo "     Then open a new shell — ~/.zshrc is already symlinked and takes over."
    step=$((step + 1))
  fi

  echo "  $step. Open Obsidian → Add Vault → select $(pwd)/vault"
  step=$((step + 1))
  echo "  $step. Settings → Community plugins → click 'Trust' for each plugin"
  echo ""
  echo "  Dashboard opens automatically and KPI cards render on first load."
}

# ── seed_vault ────────────────────────────────────────────────────────────────

seed_vault() {
  local target="$1"
  echo "==> Seeding vault at $target"

  mkdir -p "$target/.obsidian/snippets" "$target/.obsidian/plugins" \
           "$target/00-Meta/Templates" "$target/reports"

  for f in appearance.json community-plugins.json; do
    [ ! -f "$target/.obsidian/$f" ] && cp "$BASE_VAULT/.obsidian/$f" "$target/.obsidian/$f" && echo "  + .obsidian/$f"
  done

  for f in "$BASE_VAULT/.obsidian/snippets/"*.css; do
    name="$(basename "$f")"
    [ ! -f "$target/.obsidian/snippets/$name" ] && cp "$f" "$target/.obsidian/snippets/$name" && echo "  + snippets/$name"
  done

  for plugin_dir in "$BASE_VAULT/.obsidian/plugins/"/*/; do
    plugin="$(basename "$plugin_dir")"
    mkdir -p "$target/.obsidian/plugins/$plugin"
    for f in data.json manifest.json; do
      [ -f "$plugin_dir$f" ] && [ ! -f "$target/.obsidian/plugins/$plugin/$f" ] && \
        cp "$plugin_dir$f" "$target/.obsidian/plugins/$plugin/$f" && echo "  + plugins/$plugin/$f"
    done
  done

  for f in "$BASE_VAULT/00-Meta/Templates/"*.md; do
    name="$(basename "$f")"
    [ ! -f "$target/00-Meta/Templates/$name" ] && cp "$f" "$target/00-Meta/Templates/$name" && echo "  + 00-Meta/Templates/$name"
  done

  [ ! -f "$target/Dashboard.md" ] && \
    cp "$BASE_VAULT/Dashboard.md" "$target/Dashboard.md" && echo "  + Dashboard.md"
  [ ! -f "$target/reports/kpi-snapshot.json" ] && \
    cp "$BASE_VAULT/reports/kpi-snapshot.json" "$target/reports/kpi-snapshot.json" && echo "  + reports/kpi-snapshot.json"

  echo "==> seeded — run: $0 --plugins $target"
}

# ── Vault-only install (designers / product folks) ───────────────────────────

ask_persona() {
  echo ""
  echo "  Looks like gh CLI isn't set up. Quick question:"
  echo ""
  echo "  [1] Developer          — need the full dev environment"
  echo "  [2] Designer / product — just want the Obsidian vault"
  echo ""
  printf "  Your choice (1/2): "
  local choice
  read -r choice
  echo ""

  case "$choice" in
    1)
      echo "  Developer path — gh CLI needed for the full setup."
      echo ""
      echo "  Install:      brew install gh      (macOS)"
      echo "                sudo apt install gh  (Linux/WSL)"
      echo "  Authenticate: gh auth login"
      echo ""
      echo "  Then re-run: $0 --full"
      exit 0
      ;;
    2)
      echo "  Designer/product path — downloading plugins directly (no gh needed)."
      echo ""
      ;;
    *)
      echo "  Not sure? Start with the vault (option 2) — you can always"
      echo "  run $0 --full later to add dev tools."
      echo ""
      ;;
  esac
}

vault_only() {
  echo "==> studio-setup — Obsidian vault setup"

  if ! gh_available; then
    ask_persona
  fi

  install_plugins "$BASE_VAULT"

  echo ""
  echo "==> Done. One manual step:"
  echo ""
  echo "  1. Open Obsidian"
  echo "  2. Add Vault → select: $(pwd)/vault"
  echo "  3. Settings → Community plugins → click 'Trust' for each plugin"
  echo ""
  echo "  The Dashboard opens automatically. KPI cards, tasks, and project"
  echo "  tables all render on first load — no further configuration needed."
}

# ── Argument parsing ──────────────────────────────────────────────────────────

case "${1:-}" in
  --vault-only)  vault_only ;;
  --full)        full_install ;;
  --plugins)     install_plugins "${2:-$BASE_VAULT}" ;;
  --vault)       [[ -z "${2:-}" ]] && usage; seed_vault "$2" ;;
  --update-lock) update_lock ;;
  "")
    echo "==> studio-setup install"

    if ! gh_available; then
      ask_persona
      # if we get here the user picked designer/product (or typed something else)
      # route them to vault-only and stop
      vault_only
      exit 0
    fi

    echo "  wezterm"
    mkdir -p ~/.config/wezterm/workspaces
    for f in wezterm.lua utils.lua; do
      ln -sf "$REPO_DIR/wezterm/$f" ~/.config/wezterm/"$f"
      echo "    ~> ~/.config/wezterm/$f"
    done
    for f in "$REPO_DIR/wezterm/workspaces/"*.lua; do
      name="$(basename "$f")"
      [[ "$name" == "workspace.template.lua" ]] && continue
      target=~/.config/wezterm/workspaces/"$name"
      [ ! -e "$target" ] && ln -sf "$f" "$target" && echo "    ~> ~/.config/wezterm/workspaces/$name"
    done

    # ── Dotfiles ─────────────────────────────────────────────────────────

    echo "  dotfiles"

    # zshrc — back up existing, then symlink
    if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
      cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
      echo "    backed up existing ~/.zshrc"
    fi
    ln -sf "$REPO_DIR/dotfiles/zshrc" "$HOME/.zshrc"
    echo "    ~> ~/.zshrc"

    # starship prompt
    mkdir -p "$HOME/.config"
    if [ -f "$HOME/.config/starship.toml" ] && [ ! -L "$HOME/.config/starship.toml" ]; then
      cp "$HOME/.config/starship.toml" "$HOME/.config/starship.toml.bak.$(date +%Y%m%d%H%M%S)"
      echo "    backed up existing ~/.config/starship.toml"
    fi
    ln -sf "$REPO_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
    echo "    ~> ~/.config/starship.toml"

    # neovim config
    mkdir -p "$HOME/.config/nvim"
    if [ -f "$HOME/.config/nvim/init.lua" ] && [ ! -L "$HOME/.config/nvim/init.lua" ]; then
      cp "$HOME/.config/nvim/init.lua" "$HOME/.config/nvim/init.lua.bak.$(date +%Y%m%d%H%M%S)"
      echo "    backed up existing ~/.config/nvim/init.lua"
    fi
    ln -sf "$REPO_DIR/dotfiles/nvim/init.lua" "$HOME/.config/nvim/init.lua"
    echo "    ~> ~/.config/nvim/init.lua"

    # seed ~/.zshrc.local from template if none exists
    if [ ! -f "$HOME/.zshrc.local" ]; then
      cp "$REPO_DIR/dotfiles/zshrc.local.template" "$HOME/.zshrc.local"
      echo "    created ~/.zshrc.local from template"
    fi

    echo "  claude hooks"
    mkdir -p ~/.claude/hooks
    for f in "$REPO_DIR/hooks/"*.sh; do
      name="$(basename "$f")"
      ln -sf "$f" ~/.claude/hooks/"$name"
      chmod +x "$f"
      echo "    ~> ~/.claude/hooks/$name"
    done

    SETTINGS=~/.claude/settings.json
    [ ! -f "$SETTINGS" ] && echo '{}' > "$SETTINGS"

    HOOKS_JSON='{
      "PreToolUse":  [{"matcher":"Write","hooks":[{"type":"command","command":"~/.claude/hooks/file-gate.sh"}]}],
      "PostToolUse": [{"matcher":"Edit|Write","hooks":[{"type":"command","command":"~/.claude/hooks/edit-tracker.sh","async":true}]}],
      "Stop":        [{"hooks":[{"type":"command","command":"~/.claude/hooks/turn-review.sh"}]},
                      {"hooks":[{"type":"command","command":"~/.claude/hooks/session-end.sh stop"}]}],
      "SessionStart":[{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start.sh"}]}],
      "SessionEnd":  [{"hooks":[{"type":"command","command":"~/.claude/hooks/session-end.sh end"}]}]
    }'

    python3 - "$SETTINGS" "$HOOKS_JSON" <<'PYEOF'
import json, sys
settings_path = sys.argv[1]
new_hooks = json.loads(sys.argv[2])
with open(settings_path) as f:
    settings = json.load(f)
existing = settings.get("hooks", {})
for event, entries in new_hooks.items():
    if event not in existing:
        existing[event] = entries
settings["hooks"] = existing
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print("    settings.json updated")
PYEOF

    echo "==> done"
    ;;
  *) usage ;;
esac
