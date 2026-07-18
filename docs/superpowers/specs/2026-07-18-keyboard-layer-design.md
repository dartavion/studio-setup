# Keyboard-First macOS Layer — Design

**Date:** 2026-07-18
**Status:** Approved (design), pending implementation plan
**Scope:** macOS only

## Goal

Add a keyboard-only interaction layer to the studio-setup kit so a user can
launch apps, arrange windows, and click any UI element without touching the
mouse. Delivered as an **opt-in** addition to `install.sh`, following the kit's
existing install/config conventions (idempotent cask install, backup-then-symlink
for text configs, copy-seed for configs that get written back).

## Architecture — four layers, one namespace

Four apps, each owning a distinct layer, unified by a single **Hyper** key so
there is one mental model rather than four disjoint shortcut schemes.

| Layer  | App               | Owns                                                    |
|--------|-------------------|---------------------------------------------------------|
| Input  | Karabiner-Elements | Caps Lock → Hyper (held) / Escape (tapped)             |
| Launch | Raycast           | App launch, search, clipboard history, snippets         |
| Windows| AeroSpace         | Tiling, focus, move, workspaces                         |
| Click  | Homerow           | Click/scroll any UI element that has no native shortcut |

These are complementary, not overlapping: Raycast launches, AeroSpace arranges,
Homerow clicks the last-mile elements neither can reach. Karabiner is the input
foundation that makes the other three ergonomic.

### The Hyper key (decision)

`Caps(hold) = ⌃⌥⌘` — **three** modifiers, Shift deliberately left free.

Rationale: a literal Hyper (`⌘⌥⌃⇧`, all four) leaves no modifier to build a
"move window" variant on. Using three modifiers keeps Shift available so
`Hyper+key` = focus and `Hyper+Shift+key` = move. Referred to as "Hyper"
throughout for brevity; technically it is the ⌃⌥⌘ combo.

`Caps(tap) = Escape` — nvim-friendly; preserves the classic remap.

### Launcher choice (decision)

Raycast, not Alfred. Rationale: no license secret to keep out of git (Alfred
Powerpack would add a second secret alongside Homerow's), free, keyboard-first,
and it brings clipboard history + snippets built in. Raycast's built-in window
management overlaps AeroSpace's basic snapping; AeroSpace owns real
tiling/workspaces and Raycast's window hotkeys are disabled to avoid collisions.

## Keymap (collision-managed default)

This is a **starting** keymap meant to be edited, not gospel. No two bindings
collide; `⌘Space` (Raycast) is kept distinct from `Hyper+Space` (Homerow).

```
Caps (tap)              → Escape                      (nvim-friendly)
Caps (hold)             → Hyper (⌃⌥⌘)

Raycast:
  ⌘Space                → Raycast (replaces Spotlight)
  Hyper+V               → Clipboard history

AeroSpace:
  Hyper+H/J/K/L         → focus left/down/up/right
  Hyper+Shift+H/J/K/L   → move window left/down/up/right
  Hyper+1..9            → switch to workspace N
  Hyper+Shift+1..9      → move window to workspace N
  Hyper+F               → fullscreen toggle
  Hyper+Return          → layout toggle (tiles / accordion)

Homerow:
  Hyper+Space           → click mode (label + click any element)
  Hyper+S               → scroll mode
```

macOS Spotlight's `⌘Space` is disabled so Raycast can take it.

## Config location & management

Approach: install + seed configs + document the irreducibly-manual GUI/license
steps. Each app's mechanism is dictated by how it stores config, not by a single
philosophy.

| App       | Config path                                                        | Mechanism        | Why                                                                 |
|-----------|--------------------------------------------------------------------|------------------|---------------------------------------------------------------------|
| AeroSpace | `~/.config/aerospace/aerospace.toml`                               | **symlink** from repo (backup-then-link) | reads-only, never writes the file back — safe to symlink            |
| Karabiner | `~/.config/karabiner/assets/complex_modifications/studio-hyper.json` | **copy-seed** (user imports + enables in GUI) | Karabiner writes back to `karabiner.json`; seeding a rule asset avoids leaking later GUI tweaks into the repo |
| Raycast   | plist (no plain-text config)                                       | **install-only** + documented `.rayconfig` import + `defaults` to unbind window hotkeys | no symlinkable config file                                          |
| Homerow   | `com.superultra.Homerow` defaults                                 | **install-only** + manual license activation | GUI/license (see Secret handling)                                   |

New repo files:

- `dotfiles/aerospace/aerospace.toml`
- `dotfiles/karabiner/studio-hyper.json`
- `dotfiles/raycast/studio.rayconfig` (optional; ship if a clean export is
  achievable, otherwise document manual Raycast setup)

### Open implementation uncertainty

Homerow's trigger key and Raycast's window-management hotkeys are **not
documented as `defaults`-settable**. Implementation must probe whether
`defaults write` reliably sets them:

- If reliable → script them in `install.sh`.
- If not → they drop to the manual checklist rather than shipping fragile
  `defaults` writes that break on app updates.

Do not ship a `defaults` write that has not been verified to take effect.

## Secret handling (Homerow license)

- The license **never enters git.** Activation is a manual in-app step; the key
  lives only in Homerow's own storage.
- The installer prints a reminder to activate Homerow with the user's license
  key ("kept out of this repo by design"). It does **not** prompt for, echo, or
  store the key.
- Add `.gitignore` guards for `*.local` and `secrets.env` patterns so no future
  convenience file can leak a key.
- Out-of-band action for the user: rotate the license key that was pasted into
  chat during design; treat it as exposed.

## Install flow (`install.sh`, macOS-only, opt-in)

Gated behind an opt-in flag: **`install.sh --keyboard`**. Not part of the
default install — it installs four GUI apps and remaps Caps Lock, which is too
invasive to force on every kit user.

Steps performed by `--keyboard`:

1. `brew tap nikitabobko/tap` (AeroSpace is not in homebrew-core).
2. `install_cask` for: `nikitabobko/tap/aerospace`, `homerow`, `raycast`,
   `karabiner-elements`. (Note: the existing `install_cask` helper takes a bare
   cask name; it needs to accept a tap-qualified name or the tap step must run
   first.)
3. Symlink `aerospace.toml` into `~/.config/aerospace/` (backup existing
   non-symlink file first, matching the nvim/wezterm pattern).
4. Copy-seed the Karabiner rule into
   `~/.config/karabiner/assets/complex_modifications/` (skip if already present).
5. Run the verified `defaults` writes (if any survive the probe above).
6. Disable Spotlight's `⌘Space` binding.
7. Print a **manual checklist** (see below).

Idempotency: match the existing `install_cask` idempotent pattern; backup-then-
symlink for `aerospace.toml`; skip the Karabiner rule copy if the target exists.

### Manual checklist (printed at end of `--keyboard` run)

- Grant Accessibility permissions to AeroSpace, Homerow, and Karabiner-Elements
  (System Settings → Privacy & Security → Accessibility). All three require it.
- Activate Homerow with your license key.
- Open Karabiner-Elements → Complex Modifications → enable the "studio-hyper"
  rule.
- Import the Raycast config (if shipped) or set Raycast's hotkey to `⌘Space` and
  disable its window-management commands.

### Windows / cross-platform

macOS-only. `install.ps1` gets nothing from this work. Windows equivalents
(GlazeWM for tiling, PowerToys Run for launching) are **out of scope** and noted
only as possible future work; there is no Homerow analog on Windows.

## Testing

### Automatable (CI)

- `aerospace.toml` parses as valid TOML.
- `studio-hyper.json` parses as valid JSON (`jq`).
- Shellcheck on the new `install.sh` code paths.
- Existing headless install validation continues to pass.
- Optionally: assert the four cask names resolve via `brew info`.

### Not automatable

Actual keybinding behavior cannot be tested in CI — these are GUI apps that
require a logged-in session and Accessibility permissions. This is covered by a
**manual acceptance checklist**, and the spec explicitly states CI does not
cover runtime behavior:

- Caps tap emits Escape; Caps hold acts as Hyper.
- `Hyper+H/J/K/L` moves window focus.
- `Hyper+1..9` switches workspaces.
- `Hyper+Space` activates Homerow click mode.
- `⌘Space` opens Raycast (not Spotlight).

## Docs

Add a README section covering: the four-layer diagram, the keymap table, the
opt-in `--keyboard` flag, the manual setup steps, and the secret-handling note.

## Out of scope (YAGNI)

- Windows equivalents.
- Browser vim navigation (Vimium/Vimari).
- Any attempt to script license activation.
- Scripting `defaults` keys that cannot be verified to take effect.
