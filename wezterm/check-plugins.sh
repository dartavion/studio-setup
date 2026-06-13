#!/usr/bin/env bash
# Verify the wezterm plugins cloned on this machine still match the vetted SHAs in
# wezterm/plugins.lock. wezterm.plugin.require can't pin to a ref, so this is
# drift / tamper detection — NOT pinning. Run it periodically and especially after
# wezterm.plugin.update_all().
#
#   OK     — cached clone HEAD == locked SHA
#   DRIFT  — clone moved (an update or tamper); review before trusting
#   ABSENT — not cloned yet (will clone on next WezTerm launch, then re-run this)
#
# Exit 0 if everything matches/absent; exit 1 if any DRIFT is found.
set -euo pipefail

LOCK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugins.lock"
[ -f "$LOCK" ] || { echo "no plugins.lock next to this script"; exit 1; }

CACHE="$HOME/Library/Application Support/wezterm/plugins"   # macOS path
[ -d "$CACHE" ] || CACHE="$HOME/.local/share/wezterm/plugins"  # Linux fallback

# Find the cached clone dir for a given origin URL (no assoc arrays — stock macOS
# ships bash 3.2). Echoes the dir, or nothing if not cloned.
clone_for() {
  local want="$1" d u
  [ -d "$CACHE" ] || return 0
  for d in "$CACHE"/*/; do
    [ -d "$d/.git" ] || continue
    u=$(git -C "$d" config --get remote.origin.url 2>/dev/null || true)
    [ "$u" = "$want" ] && { printf '%s' "$d"; return 0; }
  done
}

drift=0
while IFS=$'\t' read -r url want; do
  [ -z "$url" ] && continue
  dir="$(clone_for "$url")"
  if [ -z "$dir" ]; then
    printf '  \033[90mABSENT\033[0m %s\n' "$url"
    continue
  fi
  have=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "?")
  if [ "$have" = "$want" ]; then
    printf '  \033[32mOK    \033[0m %s\n' "$url"
  else
    printf '  \033[33mDRIFT \033[0m %s\n        locked %s\n        cached %s\n' "$url" "$want" "$have"
    drift=1
  fi
done < <(jq -r '.plugins | to_entries[] | "\(.key)\t\(.value)"' "$LOCK")

echo
if [ "$drift" -ne 0 ]; then
  echo "Drift found. Review the upstream changes; if trusted, regenerate plugins.lock."
  exit 1
fi
echo "All cloned plugins match plugins.lock."
