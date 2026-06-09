#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_VAULT="$REPO_DIR/vault"

usage() {
  echo "Usage:"
  echo "  $0 --full                 Full setup: prerequisites + everything below"
  echo "  $0                        Install WezTerm config and Claude Code hooks"
  echo "  $0 --plugins [vault]      Download plugin binaries into vault (default: vault/)"
  echo "  $0 --vault <path>         Seed a project vault from the base vault"
  exit 1
}

# ── Full install ──────────────────────────────────────────────────────────────

full_install() {
  echo "==> studio-setup full install"

  # ── Homebrew ────────────────────────────────────────────────────────────────
  if ! command -v brew &>/dev/null; then
    echo "  installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "  homebrew ok"
  fi

  # ── Prerequisites ───────────────────────────────────────────────────────────
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

  install_cask    "WezTerm"               "wezterm"
  install_cask    "Obsidian"              "obsidian"
  install_cask    "JetBrains Mono NF"     "font-jetbrains-mono-nerd-font"
  install_formula "gh"

  if ! command -v node &>/dev/null; then
    echo "  installing node..."
    brew install node
  else
    echo "  node ok"
  fi

  if ! command -v claude &>/dev/null; then
    echo "  installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
  else
    echo "  claude ok"
  fi

  if ! gh auth status &>/dev/null; then
    echo ""
    echo "  gh is not authenticated. Run: gh auth login"
    echo "  Then re-run: $0 --full"
    exit 1
  fi

  # ── Core install (WezTerm + hooks) ──────────────────────────────────────────
  bash "$0"

  # ── Obsidian plugins + theme ────────────────────────────────────────────────
  install_plugins "$BASE_VAULT"

  echo ""
  echo "==> All done."
  echo ""
  echo "  One manual step remaining:"
  echo "  1. Open Obsidian → Add Vault → select $(pwd)/vault"
  echo "  2. Settings → Community plugins → click 'Trust' for each plugin"
  echo ""
  echo "  Dashboard opens automatically and KPI cards render on first load."
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

install_plugins() {
  local target="$1/.obsidian"
  echo "==> Installing plugins into $target"

  for entry in "${PLUGIN_IDS[@]}"; do
    local id="${entry%%:*}" repo="${entry##*:}"
    mkdir -p "$target/plugins/$id"
    echo "  $id"
    for asset in main.js manifest.json styles.css; do
      local url
      url=$(gh api "repos/$repo/releases/latest" \
        -q ".assets[] | select(.name == \"$asset\") | .browser_download_url" 2>/dev/null || true)
      [ -n "$url" ] && curl -sL "$url" -o "$target/plugins/$id/$asset"
    done
  done

  # Catppuccin theme
  local theme_dir="$target/themes/Catppuccin"
  if [ ! -f "$theme_dir/theme.css" ]; then
    echo "  Catppuccin theme"
    mkdir -p "$theme_dir"
    curl -sL "https://raw.githubusercontent.com/catppuccin/obsidian/main/theme.css"    -o "$theme_dir/theme.css"
    curl -sL "https://raw.githubusercontent.com/catppuccin/obsidian/main/manifest.json" -o "$theme_dir/manifest.json"
  fi

  echo "==> done — reload Obsidian to activate"
}

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

# ── Argument parsing ──────────────────────────────────────────────────────────

case "${1:-}" in
  --full)
    full_install
    ;;
  --plugins)
    install_plugins "${2:-$BASE_VAULT}"
    ;;
  --vault)
    [[ -z "${2:-}" ]] && usage
    seed_vault "$2"
    ;;
  "")
    echo "==> studio-setup install"

    # ── WezTerm ──────────────────────────────────────────────────────────
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
    # TODO: symlink dotfiles

    # ── Claude Code hooks ────────────────────────────────────────────────
    echo "  claude hooks"
    mkdir -p ~/.claude/hooks
    for f in "$REPO_DIR/hooks/"*.sh; do
      name="$(basename "$f")"
      ln -sf "$f" ~/.claude/hooks/"$name"
      chmod +x "$f"
      echo "    ~> ~/.claude/hooks/$name"
    done

    # Merge hook entries into ~/.claude/settings.json
    SETTINGS=~/.claude/settings.json
    if [ ! -f "$SETTINGS" ]; then
      echo '{}' > "$SETTINGS"
    fi

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
  *)
    usage
    ;;
esac
