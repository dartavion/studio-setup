#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> studio-setup install"

# ── WezTerm ──────────────────────────────────────────────────────────────────
# TODO: symlink wezterm config

# ── Obsidian ─────────────────────────────────────────────────────────────────
# TODO: copy snippets and templates into vault

# ── Dotfiles ─────────────────────────────────────────────────────────────────
# TODO: symlink dotfiles

# ── Claude Code hooks ────────────────────────────────────────────────────────
# TODO: symlink hooks into ~/.claude/hooks/

echo "==> done"
