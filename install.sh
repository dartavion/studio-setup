#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_VAULT="$REPO_DIR/vault"

usage() {
  echo "Usage:"
  echo "  $0                        Install WezTerm, dotfiles, and Claude Code hooks"
  echo "  $0 --plugins [vault]      Download plugin binaries into vault (default: vault/)"
  echo "  $0 --vault <path>         Seed a project vault from the base vault"
  exit 1
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
  --plugins)
    install_plugins "${2:-$BASE_VAULT}"
    ;;
  --vault)
    [[ -z "${2:-}" ]] && usage
    seed_vault "$2"
    ;;
  "")
    echo "==> studio-setup install"
    # ── WezTerm ────────────────────────────────────────────────────────────
    # TODO: symlink wezterm config

    # ── Dotfiles ───────────────────────────────────────────────────────────
    # TODO: symlink dotfiles

    # ── Claude Code hooks ──────────────────────────────────────────────────
    # TODO: symlink hooks into ~/.claude/hooks/

    echo "==> done"
    ;;
  *)
    usage
    ;;
esac
