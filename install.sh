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
  echo "  $0 --keyboard             macOS keyboard-first layer: aerospace, homerow, raycast, karabiner (opt-in)"
  exit 1
}

# ── Security helpers ──────────────────────────────────────────────────────────

pinned_version() {
  local id="$1"
  python3 - "$LOCK_FILE" "$id" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(d['plugins'].get(sys.argv[2], 'latest'))
PYEOF
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
  [ "${UPDATING_LOCK:-0}" = "1" ] && return 0  # updating lock — skip validation of old hash
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

verify_and_run_script() {
  local id="$1" url="$2" runner="$3"
  shift 3
  local expected actual temp_file
  expected="$(stored_checksum "$id")"
  if [ -z "$expected" ]; then
    echo "  !! No stored checksum found for $id"
    exit 1
  fi
  temp_file="$(mktemp)"
  if curl -fsSL "$url" -o "$temp_file"; then
    actual="$(shasum -a 256 "$temp_file" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
      echo ""
      echo "  !! SECURITY VIOLATION: Checksum mismatch for external installer: $id"
      echo "     URL:      $url"
      echo "     Expected: $expected"
      echo "     Actual:   $actual"
      echo "     Aborting execution for safety."
      rm -f "$temp_file"
      exit 1
    fi
    "$runner" "$temp_file" "$@"
    rm -f "$temp_file"
  else
    echo "  !! Failed to download installer from $url"
    exit 1
  fi
}


# ── Plugin manifest: id -> github_repo ───────────────────────────────────────

PLUGIN_IDS=(
  "catppuccin-obsidian:catppuccin/obsidian"
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
    if [ -n "$url" ]; then
      if curl -fsL "$url" -o "$dest" 2>/dev/null; then
        return 0
      fi
    fi
  fi

  return 1
}

install_plugins() {
  local target="$1/.obsidian"
  echo "==> Installing plugins into $target"

  for entry in "${PLUGIN_IDS[@]}"; do
    local id="${entry%%:*}" repo="${entry##*:}"
    # catppuccin-obsidian is a theme, not an Obsidian plugin — installed separately below
    [ "$id" = "catppuccin-obsidian" ] && continue
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
      elif [ "$asset" = "main.js" ]; then
        echo "  warning: $id main.js download failed — plugin will not load"
        if [ "${UPDATING_LOCK:-0}" = "1" ]; then
          echo "  Error: $id main.js download failed during lock update. Aborting." >&2
          return 1
        fi
      fi
    done
  done

  # Catppuccin theme — pinned via versions.lock key "catppuccin-obsidian"
  local theme_dir="$target/themes/Catppuccin"
  if [ ! -f "$theme_dir/theme.css" ]; then
    echo "  Catppuccin theme"
    mkdir -p "$theme_dir"
    local theme_version
    theme_version="$(pinned_version "catppuccin-obsidian")"
    local theme_ok=0
    if [ "$theme_version" != "latest" ]; then
      if curl -fsL "https://github.com/catppuccin/obsidian/releases/download/${theme_version}/theme.css" \
            -o "$theme_dir/theme.css" 2>/dev/null && \
         curl -fsL "https://github.com/catppuccin/obsidian/releases/download/${theme_version}/manifest.json" \
            -o "$theme_dir/manifest.json" 2>/dev/null; then
        theme_ok=1
      fi
    fi
    if [ $theme_ok -eq 0 ]; then
      echo "  warning: Catppuccin theme download failed — vault will open without theme"
      if [ "${UPDATING_LOCK:-0}" = "1" ]; then
        echo "  Error: Catppuccin theme download failed during lock update. Aborting." >&2
        return 1
      fi
    else
      echo "  Catppuccin theme ok"
    fi
  fi

  echo "==> plugins installed and verified"
}

# ── Update lockfile ───────────────────────────────────────────────────────────

update_lock() {
  export UPDATING_LOCK=1
  echo "==> Updating versions.lock and checksums.sha256"
  echo ""
  echo "  SECURITY NOTICE"
  echo "  This command downloads new plugin binaries and recomputes their checksums"
  echo "  from what it just downloaded. It trusts the download implicitly."
  echo "  If those binaries were tampered with, the new checksums would verify them."
  echo ""
  echo "  Before committing:"
  echo "    - Use a trusted network (not public Wi-Fi)"
  echo "    - Review: git diff versions.lock checksums.sha256"
  echo "    - Only versions.lock and checksums.sha256 should change"
  echo "    - Prefer opening a PR over pushing directly to main"
  echo "    - Consider triggering the GitHub Actions workflow instead —"
  echo "      it runs tamper detection before updating anything"
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
  echo "$versions_json" | python3 -m json.tool > "$LOCK_FILE.tmp"

  # Wipe existing main.js files so stale copies can't be checksummed on download failure
  shopt -s nullglob
  for dir in "$BASE_VAULT/.obsidian/plugins"/*/; do
    rm -f "$dir/main.js"
  done
  shopt -u nullglob

  # Re-download and recompute checksums
  if ! install_plugins "$BASE_VAULT"; then
    echo "  Error: failed to install one or more plugins during lock update. Aborting." >&2
    rm -f "$LOCK_FILE.tmp" "$CHECKSUM_FILE.tmp"
    exit 1
  fi

  printf "# SHA256 checksums for plugin main.js files at pinned versions\n" > "$CHECKSUM_FILE.tmp"
  printf "# Regenerate with: ./install.sh --update-lock\n\n" >> "$CHECKSUM_FILE.tmp"
  shopt -s nullglob
  for dir in "$BASE_VAULT/.obsidian/plugins"/*/; do
    local id
    id="$(basename "$dir")"
    [ -f "$dir/main.js" ] && \
      echo "$id=$(shasum -a 256 "$dir/main.js" | awk '{print $1}')" >> "$CHECKSUM_FILE.tmp"
  done
  shopt -u nullglob

  # Re-download installer scripts and compute their checksums
  echo "==> Updating installer script checksums"
  local installers=(
    "installer-nvm:https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh"
    "installer-starship:https://starship.rs/install.sh"
    "installer-zoxide:https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"
    "installer-scoop:https://get.scoop.sh"
  )

  printf "\n# SHA256 checksums for external installer scripts\n" >> "$CHECKSUM_FILE.tmp"
  for entry in "${installers[@]}"; do
    local name="${entry%%:*}" url="${entry#*:}"
    local tmp_file sum
    tmp_file="$(mktemp)"
    if curl -fsSL "$url" -o "$tmp_file"; then
      sum="$(shasum -a 256 "$tmp_file" | awk '{print $1}')"
      echo "$name=$sum" >> "$CHECKSUM_FILE.tmp"
      echo "  $name -> $sum"
    else
      echo "  Error: failed to fetch $name to update checksum. Aborting." >&2
      rm -f "$tmp_file"
      rm -f "$LOCK_FILE.tmp" "$CHECKSUM_FILE.tmp"
      exit 1
    fi
    rm -f "$tmp_file"
  done

  mv "$LOCK_FILE.tmp" "$LOCK_FILE"
  mv "$CHECKSUM_FILE.tmp" "$CHECKSUM_FILE"

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
  apt_install build-essential   # C compiler for nvim-treesitter (main) parser builds via the tree-sitter CLI
  apt_install jq                # required by the Claude Code hooks (cost tracking, git-guard, etc.)

  if ! command -v node &>/dev/null; then
    echo "  installing Node.js via nvm..."
    verify_and_run_script "installer-nvm" "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh" bash
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
  else
    echo "  node ok"
  fi

  # nvm-installed node may not be on PATH in a fresh non-interactive shell
  [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"
  if ! command -v tree-sitter &>/dev/null; then
    echo "  installing tree-sitter CLI (nvim-treesitter main branch builds parsers with it)..."
    npm install -g tree-sitter-cli
  else
    echo "  tree-sitter ok"
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
    verify_and_run_script "installer-starship" "https://starship.rs/install.sh" sh --yes
  else
    echo "  starship ok"
  fi

  if ! command -v eza &>/dev/null; then
    echo "  installing eza..."
    sudo install -m 0755 -d /etc/apt/keyrings
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
    verify_and_run_script "installer-zoxide" "https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh" sh
  else
    echo "  zoxide ok"
  fi

  echo ""
  echo "  WSL note: set zsh as default shell with:  chsh -s \$(which zsh)"
  echo ""

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
  echo "  Open Obsidian on the Windows side → Add Vault → select vault/"
  echo "  Settings → Community plugins → click 'Trust' for each plugin"
  echo ""
  echo "  Note: WezTerm and Obsidian run on Windows, not inside WSL."
  echo "  From WezTerm, open a WSL tab: New Tab → Ubuntu (or your distro)"
}

install_cask() {
  local app="$1" cask="$2"
  if brew list --cask "$cask" &>/dev/null; then
    echo "  $app ok"
    return
  fi
  # If the app is already installed manually (outside brew), leave it untouched.
  # Do NOT use --adopt: a failed adopt rolls back by DELETING the user's app.
  if [ -d "/Applications/$app.app" ]; then
    echo "  $app already present (not brew-managed) — skipping"
    return
  fi
  echo "  installing $cask..."
  brew install --cask "$cask" \
    || echo "  warning: could not install $cask — continuing"
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

keyboard_layer_install() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "  --keyboard is macOS only — nothing to do on this platform"
    return 0
  fi
  echo "==> studio-setup keyboard-first layer (macOS)"

  if ! command -v brew &>/dev/null; then
    echo "  Homebrew required. Run: $0 --full   (or install brew first)"
    return 1
  fi

  echo "  tapping nikitabobko/tap (AeroSpace is not in homebrew-core)..."
  brew tap nikitabobko/tap &>/dev/null || echo "  warning: could not tap nikitabobko/tap — AeroSpace may fail"

  install_cask "AeroSpace"          "nikitabobko/tap/aerospace"
  install_cask "Homerow"            "homerow"
  install_cask "Raycast"            "raycast"
  install_cask "Karabiner-Elements" "karabiner-elements"

  echo "  aerospace config"
  mkdir -p "$HOME/.config/aerospace"
  if [ -f "$HOME/.config/aerospace/aerospace.toml" ] && [ ! -L "$HOME/.config/aerospace/aerospace.toml" ]; then
    cp "$HOME/.config/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml.bak.$(date +%Y%m%d%H%M%S)"
    echo "    backed up existing ~/.config/aerospace/aerospace.toml"
  fi
  ln -sf "$REPO_DIR/dotfiles/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
  echo "    ~> ~/.config/aerospace/aerospace.toml"

  echo "  karabiner rule (copy-seed; enable it in the Karabiner GUI)"
  karabiner_rules="$HOME/.config/karabiner/assets/complex_modifications"
  mkdir -p "$karabiner_rules"
  if [ -e "$karabiner_rules/studio-hyper.json" ]; then
    echo "    studio-hyper.json already present — leaving it"
  else
    cp "$REPO_DIR/dotfiles/karabiner/studio-hyper.json" "$karabiner_rules/studio-hyper.json"
    echo "    ~> $karabiner_rules/studio-hyper.json"
  fi

  cat <<'CHECKLIST'

  ==> Manual steps (these cannot be scripted safely):
    1. Grant Accessibility permissions to AeroSpace, Homerow, and
       Karabiner-Elements:
         System Settings -> Privacy & Security -> Accessibility
       (All three need it; without it, shortcuts silently do nothing.)
    2. Activate Homerow with your license key — your key is
       kept out of this repo by design. Enter it directly in the Homerow app.
    3. Karabiner-Elements -> Complex Modifications -> Add rule ->
       enable "studio-hyper" (Caps Lock becomes Hyper on hold, Escape on tap).
    4. Open Raycast and complete onboarding: set its hotkey to Cmd+Space
       (Raycast offers to disable Spotlight's Cmd+Space for you), and
       disable Raycast's own window-management commands so they don't
       collide with AeroSpace.

  Keymap reference: see README (search "keyboard-first").
CHECKLIST
}

full_install_macos() {
  # ── Homebrew ────────────────────────────────────────────────────────────────
  if ! command -v brew &>/dev/null; then
    echo "  installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "  homebrew ok"
  fi

  install_cask    "WezTerm"           "wezterm"
  install_cask    "Obsidian"          "obsidian"
  install_cask    "JetBrains Mono NF" "font-jetbrains-mono-nerd-font"
  install_formula "gh"
  install_formula "node"
  install_formula "neovim"
  install_formula "tree-sitter-cli"   # nvim-treesitter (main branch) shells out to the tree-sitter CLI to compile parsers
  install_formula "jq"                 # required by the Claude Code hooks (cost tracking, git-guard, etc.)
  install_formula "starship"
  install_formula "eza"
  install_formula "bat"
  install_formula "fzf"
  install_formula "fd"
  install_formula "zoxide"
  install_formula "zsh-autosuggestions"
  install_formula "zsh-syntax-highlighting"
  install_formula "ripgrep"

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

  echo "  Manual steps required:"
  echo ""
  echo "  1. Open Obsidian → Add Vault → select $(pwd)/vault"
  echo "  2. Settings → Community plugins → click 'Trust' for each plugin"
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

  shopt -s nullglob
  for plugin_dir in "$BASE_VAULT/.obsidian/plugins"/*/; do
    plugin="$(basename "$plugin_dir")"
    mkdir -p "$target/.obsidian/plugins/$plugin"
    for f in data.json manifest.json; do
      [ -f "$plugin_dir$f" ] && [ ! -f "$target/.obsidian/plugins/$plugin/$f" ] && \
        cp "$plugin_dir$f" "$target/.obsidian/plugins/$plugin/$f" && echo "  + plugins/$plugin/$f"
    done
  done
  shopt -u nullglob

  for f in "$BASE_VAULT/00-Meta/Templates/"*.md; do
    name="$(basename "$f")"
    [ ! -f "$target/00-Meta/Templates/$name" ] && cp "$f" "$target/00-Meta/Templates/$name" && echo "  + 00-Meta/Templates/$name"
  done

  [ ! -f "$target/Dashboard.md" ] && \
    cp "$BASE_VAULT/Dashboard.md" "$target/Dashboard.md" && echo "  + Dashboard.md"
  [ ! -f "$target/reports/kpi-snapshot.json" ] && \
    cp "$BASE_VAULT/reports/kpi-snapshot.json" "$target/reports/kpi-snapshot.json" && echo "  + reports/kpi-snapshot.json"

  install_plugins "$target"
}

# ── Vault-only install (designers / product folks) ───────────────────────────

ask_persona() {
  # non-interactive shell (piped input, CI) — skip prompt, default to vault-only
  if [ ! -t 0 ]; then
    echo "  Non-interactive shell — defaulting to vault-only."
    echo ""
    return 0
  fi

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

  install_plugins "$BASE_VAULT"

  echo ""
  echo "==> Done. One manual step:"
  echo ""
  echo "  1. Open Obsidian"
  echo "  2. Add Vault → select: $REPO_DIR/vault"
  echo "  3. Settings → Community plugins → click 'Trust' for each plugin"
  echo ""
  echo "  The Dashboard opens automatically. KPI cards, tasks, and project"
  echo "  tables all render on first load — no further configuration needed."
}

# ── Argument parsing ──────────────────────────────────────────────────────────

case "${1:-}" in
  --vault-only)
    if ! gh_available; then ask_persona; fi
    vault_only
    ;;
  --full)        full_install ;;
  --plugins)     install_plugins "${2:-$BASE_VAULT}" ;;
  --vault)       [[ -z "${2:-}" ]] && usage; seed_vault "$2" ;;
  --update-lock) update_lock ;;
  --keyboard)    keyboard_layer_install ;;
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
    # helper scripts used by wezterm.lua (e.g. the tabline spend component)
    if [ -d "$REPO_DIR/wezterm/scripts" ]; then
      mkdir -p ~/.config/wezterm/scripts
      for f in "$REPO_DIR/wezterm/scripts/"*; do
        ln -sf "$f" ~/.config/wezterm/scripts/"$(basename "$f")"
        echo "    ~> ~/.config/wezterm/scripts/$(basename "$f")"
      done
    fi

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

    # If starship is installed, prefer generating the tokyo-night preset locally.
    # If generation fails (or starship missing), fall back to the repo-provided config.
    if command -v starship >/dev/null 2>&1; then
      if [ ! -e "$HOME/.config/starship.toml" ]; then
        echo "    generating starship preset: tokyo-night -> ~/.config/starship.toml"
        if ! starship preset tokyo-night -o "$HOME/.config/starship.toml" 2>/dev/null; then
          echo "    warning: starship preset failed, copying repo default"
          cp "$REPO_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
        fi
        echo "    ~> ~/.config/starship.toml"
      else
        echo "    ~/.config/starship.toml already exists — kept"
      fi
    else
      ln -sf "$REPO_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
      echo "    ~> ~/.config/starship.toml"
    fi

    # neovim config
    mkdir -p "$HOME/.config/nvim"
    if [ -f "$HOME/.config/nvim/init.lua" ] && [ ! -L "$HOME/.config/nvim/init.lua" ]; then
      cp "$HOME/.config/nvim/init.lua" "$HOME/.config/nvim/init.lua.bak.$(date +%Y%m%d%H%M%S)"
      echo "    backed up existing ~/.config/nvim/init.lua"
    fi
    ln -sf "$REPO_DIR/dotfiles/nvim/init.lua" "$HOME/.config/nvim/init.lua"
    echo "    ~> ~/.config/nvim/init.lua"

    # nvim plugin lockfile — COPIED (not symlinked) so a later ':Lazy update'
    # writes the user's own copy, never the repo. Pins plugins to the versions
    # the kit was tested against (same reproducibility bar as the Obsidian plugins).
    if [ -f "$REPO_DIR/dotfiles/nvim/lazy-lock.json" ]; then
      cp "$REPO_DIR/dotfiles/nvim/lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"
      echo "    ~> ~/.config/nvim/lazy-lock.json (pinned)"
      if command -v nvim >/dev/null 2>&1; then
        echo "    installing + pinning nvim plugins (first run may take a minute)…"
        nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 || \
          echo "    note: open nvim and run ':Lazy restore' if plugins aren't pinned"
        # nvim-treesitter (main branch) compiles parsers via the tree-sitter CLI.
        # --full installs it; a bare ./install.sh assumes prerequisites, so just warn.
        command -v tree-sitter >/dev/null 2>&1 || \
          echo "    note: 'tree-sitter' CLI not found — install it (brew install tree-sitter-cli) or treesitter highlighting won't build"
      fi
    fi

    # seed ~/.zshrc.local from template if none exists
    if [ ! -f "$HOME/.zshrc.local" ]; then
      cp "$REPO_DIR/dotfiles/zshrc.local.template" "$HOME/.zshrc.local"
      echo "    created ~/.zshrc.local from template"
    fi

    # global Claude CLAUDE.md — append Epistemic Honesty if not already present
    CLAUDE_MD="$HOME/.claude/CLAUDE.md"
    mkdir -p "$HOME/.claude"
    if ! grep -q "## Epistemic Honesty" "$CLAUDE_MD" 2>/dev/null; then
      printf '\n' >> "$CLAUDE_MD"
      cat "$REPO_DIR/dotfiles/claude-global.md" >> "$CLAUDE_MD"
      echo "    ~> ~/.claude/CLAUDE.md (Epistemic Honesty appended)"
    else
      echo "    ~/.claude/CLAUDE.md already contains Epistemic Honesty — skipped"
    fi

    echo "  claude hooks"
    mkdir -p ~/.claude/hooks
    for f in "$REPO_DIR/hooks/"*.sh; do
      name="$(basename "$f")"
      ln -sf "$f" ~/.claude/hooks/"$name"
      chmod +x "$f"
      echo "    ~> ~/.claude/hooks/$name"
    done
    # symlink supporting config files alongside the hooks
    for f in "$REPO_DIR/hooks/"*.json; do
      name="$(basename "$f")"
      ln -sf "$f" ~/.claude/hooks/"$name"
      echo "    ~> ~/.claude/hooks/$name"
    done

    SETTINGS=~/.claude/settings.json
    [ ! -f "$SETTINGS" ] && echo '{}' > "$SETTINGS"

    HOOKS_JSON='{
      "PreToolUse":  [{"matcher":"Write","hooks":[{"type":"command","command":"~/.claude/hooks/file-gate.sh"}]},
                      {"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/git-guard.sh"}]}],
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
    else:
        # merge at the command level — don't add duplicates
        existing_cmds = {
            h.get("command")
            for entry in existing[event]
            for h in entry.get("hooks", [])
        }
        for entry in entries:
            for h in entry.get("hooks", []):
                if h.get("command") not in existing_cmds:
                    existing[event].append(entry)
                    existing_cmds.add(h.get("command"))
                    break
settings["hooks"] = existing
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print("    settings.json updated")
PYEOF

    echo "==> done"
    ;;
  *) usage ;;
esac
