#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_VAULT="$REPO_DIR/vault"

usage() {
  echo "Usage: $0 [--vault <target-path>]"
  echo ""
  echo "  --vault <path>   Seed a new Obsidian vault at <path> from the base vault."
  echo "                   Merges .obsidian config and copies templates."
  echo "                   Safe to re-run — existing files are not overwritten."
  echo ""
  echo "  (no args)        Install WezTerm, dotfiles, and Claude Code hooks."
  exit 1
}

seed_vault() {
  local target="$1"
  echo "==> Seeding vault at $target"

  mkdir -p "$target/.obsidian/snippets" "$target/.obsidian/plugins" "$target/00-Meta/Templates" "$target/reports"

  # .obsidian config — copy only if not already present
  for f in appearance.json community-plugins.json; do
    [ ! -f "$target/.obsidian/$f" ] && cp "$BASE_VAULT/.obsidian/$f" "$target/.obsidian/$f" && echo "  + .obsidian/$f"
  done

  # Snippets — copy only if not already present
  for f in "$BASE_VAULT/.obsidian/snippets/"*.css; do
    name="$(basename "$f")"
    [ ! -f "$target/.obsidian/snippets/$name" ] && cp "$f" "$target/.obsidian/snippets/$name" && echo "  + snippets/$name"
  done

  # Plugin configs — copy only if not already present
  for plugin_dir in "$BASE_VAULT/.obsidian/plugins/"/*/; do
    plugin="$(basename "$plugin_dir")"
    mkdir -p "$target/.obsidian/plugins/$plugin"
    for f in data.json manifest.json; do
      [ -f "$plugin_dir$f" ] && [ ! -f "$target/.obsidian/plugins/$plugin/$f" ] && \
        cp "$plugin_dir$f" "$target/.obsidian/plugins/$plugin/$f" && echo "  + plugins/$plugin/$f"
    done
  done

  # Templates
  for f in "$BASE_VAULT/00-Meta/Templates/"*.md; do
    name="$(basename "$f")"
    [ ! -f "$target/00-Meta/Templates/$name" ] && cp "$f" "$target/00-Meta/Templates/$name" && echo "  + 00-Meta/Templates/$name"
  done

  # Dashboard + KPI snapshot
  [ ! -f "$target/Dashboard.md" ]              && cp "$BASE_VAULT/Dashboard.md"              "$target/Dashboard.md"              && echo "  + Dashboard.md"
  [ ! -f "$target/reports/kpi-snapshot.json" ] && cp "$BASE_VAULT/reports/kpi-snapshot.json" "$target/reports/kpi-snapshot.json" && echo "  + reports/kpi-snapshot.json"

  echo "==> vault seeded — open $target in Obsidian, then install plugins via Community Plugins"
}

# ── Argument parsing ──────────────────────────────────────────────────────────

if [[ "${1:-}" == "--vault" ]]; then
  [[ -z "${2:-}" ]] && usage
  seed_vault "$2"
  exit 0
fi

echo "==> studio-setup install"

# ── WezTerm ──────────────────────────────────────────────────────────────────
# TODO: symlink wezterm config

# ── Dotfiles ─────────────────────────────────────────────────────────────────
# TODO: symlink dotfiles

# ── Claude Code hooks ────────────────────────────────────────────────────────
# TODO: symlink hooks into ~/.claude/hooks/

echo "==> done"
