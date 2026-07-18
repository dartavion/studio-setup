# Keyboard-First macOS Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `install.sh --keyboard` path that installs and configures a four-layer keyboard-only macOS stack (Karabiner, Raycast, AeroSpace, Homerow).

**Architecture:** A single new `keyboard_layer_install()` function in `install.sh`, dispatched by `--keyboard`, that taps + installs four casks, symlinks the AeroSpace TOML, copy-seeds a Karabiner rule asset, and prints a manual checklist for the irreducibly-GUI steps (license activation, Accessibility grants, rule enable, Raycast onboarding). Config files live under `dotfiles/`. GUI/license steps are documented, never scripted with unverified `defaults` writes.

**Tech Stack:** Bash (install.sh), Homebrew casks, TOML (AeroSpace), JSON (Karabiner complex_modifications), GitHub Actions CI (shellcheck + `bash -n` + grep/parse assertions).

## Global Constraints

- **macOS only.** No changes to `install.ps1`. Windows equivalents are out of scope.
- **Opt-in.** All work is gated behind `install.sh --keyboard`; the default and `--full` paths are unchanged.
- **Hyper = `⌃⌥⌘` (three modifiers, Shift free).** AeroSpace binds literally to `ctrl-alt-cmd-*`; the Karabiner rule emits `left_command + left_control + left_option` on Caps-hold.
- **No secrets in git.** The Homerow license is never prompted for, echoed, or stored. Never script an unverified `defaults` write.
- **Idempotency.** Match the existing `install_cask` pattern: re-running `--keyboard` must be safe. Backup-then-symlink for text configs; skip copy-seed if the target exists.
- **Config paths:** AeroSpace `~/.config/aerospace/aerospace.toml`; Karabiner `~/.config/karabiner/assets/complex_modifications/studio-hyper.json`.
- **Cask names:** `nikitabobko/tap/aerospace` (needs `brew tap nikitabobko/tap`), `homerow`, `raycast`, `karabiner-elements`.
- **Validators available:** `python3 -c "import tomllib"`, `jq`. Both confirmed present locally and on macOS CI runners.

---

### Task 1: `--keyboard` flag scaffold + cask installation

**Files:**
- Modify: `install.sh` — `usage()` (around line 9-18), new `keyboard_layer_install()` function (add near `full_install_macos()` at line 418), dispatch `case` (line 605-786).

**Interfaces:**
- Produces: shell function `keyboard_layer_install()` (no args), invoked by `install.sh --keyboard`. Reuses the existing `install_cask "AppName" "cask"` helper defined inside `full_install_macos()` — NOTE that helper is currently a nested function, so Task 1 must define its own top-level cask helper or inline the `brew install --cask` calls. This plan inlines a small local helper inside `keyboard_layer_install()` to avoid coupling to `full_install_macos`'s scope.

- [ ] **Step 1: Write the failing assertion**

Create a scratch check (run from repo root). This is the "test" — it mirrors the grep-based structural assertions in `.github/workflows/macos.yml`:

```bash
bash -n install.sh \
  && grep -qE '^\s*--keyboard\)' install.sh \
  && grep -q 'keyboard_layer_install' install.sh \
  && grep -q '\-\-keyboard' install.sh \
  && echo PASS || echo FAIL
```

- [ ] **Step 2: Run it to verify it fails**

Run the block above.
Expected: `FAIL` (no `--keyboard` wiring yet).

- [ ] **Step 3: Add the usage line**

In `usage()` (after the `--update-lock` line, ~line 16), add:

```bash
  echo "  $0 --keyboard             macOS keyboard-first layer: aerospace, homerow, raycast, karabiner (opt-in)"
```

- [ ] **Step 4: Add the `keyboard_layer_install()` function**

Insert this complete function immediately above `full_install_macos() {` (line 418):

```bash
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

  # local cask helper — mirrors full_install_macos's install_cask but scoped here
  kb_install_cask() {
    local app="$1" cask="$2"
    if brew list --cask "$cask" &>/dev/null; then
      echo "  $app ok"; return
    fi
    if [ -d "/Applications/$app.app" ]; then
      echo "  $app already present (not brew-managed) — skipping"; return
    fi
    echo "  installing $cask..."
    brew install --cask "$cask" \
      || echo "  warning: could not install $cask — continuing"
  }

  echo "  tapping nikitabobko/tap (AeroSpace is not in homebrew-core)..."
  brew tap nikitabobko/tap &>/dev/null || echo "  warning: could not tap nikitabobko/tap — AeroSpace may fail"

  kb_install_cask "AeroSpace"          "nikitabobko/tap/aerospace"
  kb_install_cask "Homerow"            "homerow"
  kb_install_cask "Raycast"            "raycast"
  kb_install_cask "Karabiner-Elements" "karabiner-elements"
}
```

- [ ] **Step 5: Wire the dispatch**

In the `case "${1:-}" in` block (line 605), add a branch after `--update-lock)`:

```bash
  --keyboard)    keyboard_layer_install ;;
```

- [ ] **Step 6: Run the assertion to verify it passes**

Run the Step 1 block.
Expected: `PASS`.

- [ ] **Step 7: Run shellcheck (matches CI severity gate)**

Run: `shellcheck --severity=error install.sh`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add install.sh
git commit -m "feat(install): add opt-in --keyboard scaffold + cask installs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: AeroSpace config + symlink step

**Files:**
- Create: `dotfiles/aerospace/aerospace.toml`
- Modify: `install.sh` — append a symlink step to `keyboard_layer_install()`.
- Test: parse/content assertion (inline shell).

**Interfaces:**
- Consumes: `keyboard_layer_install()` from Task 1; `$REPO_DIR` (repo root, already defined near the top of install.sh and used by the wezterm/nvim symlink code).
- Produces: symlink `~/.config/aerospace/aerospace.toml -> $REPO_DIR/dotfiles/aerospace/aerospace.toml`.

- [ ] **Step 1: Write the failing assertion**

```bash
python3 -c "import tomllib,sys; d=tomllib.load(open('dotfiles/aerospace/aerospace.toml','rb')); b=d['mode']['main']['binding']; assert b['ctrl-alt-cmd-h']=='focus left'; assert b['ctrl-alt-cmd-shift-1']=='move-node-to-workspace 1'; assert b['ctrl-alt-cmd-1']=='workspace 1'; print('PASS')" 2>&1
```

- [ ] **Step 2: Run it to verify it fails**

Run the block above.
Expected: failure (`FileNotFoundError` — the file does not exist yet).

- [ ] **Step 3: Create the AeroSpace config**

Create `dotfiles/aerospace/aerospace.toml`:

```toml
# studio-setup AeroSpace config — keyboard-first tiling
# Hyper = Ctrl+Alt+Cmd (emitted by the Karabiner "studio-hyper" rule on Caps-hold).
# Edit freely; this is a starting keymap, not gospel.

start-at-login = true
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.right = 8
outer.top = 8
outer.bottom = 8

[mode.main.binding]
# focus
ctrl-alt-cmd-h = 'focus left'
ctrl-alt-cmd-j = 'focus down'
ctrl-alt-cmd-k = 'focus up'
ctrl-alt-cmd-l = 'focus right'

# move window
ctrl-alt-cmd-shift-h = 'move left'
ctrl-alt-cmd-shift-j = 'move down'
ctrl-alt-cmd-shift-k = 'move up'
ctrl-alt-cmd-shift-l = 'move right'

# switch workspace
ctrl-alt-cmd-1 = 'workspace 1'
ctrl-alt-cmd-2 = 'workspace 2'
ctrl-alt-cmd-3 = 'workspace 3'
ctrl-alt-cmd-4 = 'workspace 4'
ctrl-alt-cmd-5 = 'workspace 5'
ctrl-alt-cmd-6 = 'workspace 6'
ctrl-alt-cmd-7 = 'workspace 7'
ctrl-alt-cmd-8 = 'workspace 8'
ctrl-alt-cmd-9 = 'workspace 9'

# move window to workspace
ctrl-alt-cmd-shift-1 = 'move-node-to-workspace 1'
ctrl-alt-cmd-shift-2 = 'move-node-to-workspace 2'
ctrl-alt-cmd-shift-3 = 'move-node-to-workspace 3'
ctrl-alt-cmd-shift-4 = 'move-node-to-workspace 4'
ctrl-alt-cmd-shift-5 = 'move-node-to-workspace 5'
ctrl-alt-cmd-shift-6 = 'move-node-to-workspace 6'
ctrl-alt-cmd-shift-7 = 'move-node-to-workspace 7'
ctrl-alt-cmd-shift-8 = 'move-node-to-workspace 8'
ctrl-alt-cmd-shift-9 = 'move-node-to-workspace 9'

# layout
ctrl-alt-cmd-f = 'fullscreen'
ctrl-alt-cmd-enter = 'layout tiles accordion'
```

- [ ] **Step 4: Run the assertion to verify it passes**

Run the Step 1 block.
Expected: `PASS`.

- [ ] **Step 5: Add the symlink step to `keyboard_layer_install()`**

Append inside `keyboard_layer_install()`, after the cask installs (before the closing `}`):

```bash
  echo "  aerospace config"
  mkdir -p "$HOME/.config/aerospace"
  if [ -f "$HOME/.config/aerospace/aerospace.toml" ] && [ ! -L "$HOME/.config/aerospace/aerospace.toml" ]; then
    cp "$HOME/.config/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml.bak.$(date +%Y%m%d%H%M%S)"
    echo "    backed up existing ~/.config/aerospace/aerospace.toml"
  fi
  ln -sf "$REPO_DIR/dotfiles/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
  echo "    ~> ~/.config/aerospace/aerospace.toml"
```

- [ ] **Step 6: Verify shell still parses**

Run: `bash -n install.sh && shellcheck --severity=error install.sh && echo OK`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add dotfiles/aerospace/aerospace.toml install.sh
git commit -m "feat(keyboard): aerospace tiling config + symlink step

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Karabiner Hyper rule + copy-seed step

**Files:**
- Create: `dotfiles/karabiner/studio-hyper.json`
- Modify: `install.sh` — append copy-seed step to `keyboard_layer_install()`.

**Interfaces:**
- Consumes: `keyboard_layer_install()`, `$REPO_DIR`.
- Produces: copied file at `~/.config/karabiner/assets/complex_modifications/studio-hyper.json` (user enables it in the Karabiner GUI).

- [ ] **Step 1: Write the failing assertion**

```bash
jq -e '.rules[0].manipulators[0]
       | (.from.key_code=="caps_lock")
       and (.to[0].key_code=="left_command")
       and (.to[0].modifiers==["left_control","left_option"])
       and (.to_if_alone[0].key_code=="escape")' \
  dotfiles/karabiner/studio-hyper.json >/dev/null && echo PASS || echo FAIL
```

- [ ] **Step 2: Run it to verify it fails**

Run the block above.
Expected: `FAIL` (file missing — `jq` errors, prints `FAIL`).

- [ ] **Step 3: Create the Karabiner rule**

Create `dotfiles/karabiner/studio-hyper.json`:

```json
{
  "title": "studio-hyper",
  "rules": [
    {
      "description": "Caps Lock → Hyper (Ctrl+Alt+Cmd) when held, Escape when tapped",
      "manipulators": [
        {
          "type": "basic",
          "from": {
            "key_code": "caps_lock",
            "modifiers": { "optional": ["any"] }
          },
          "to": [
            {
              "key_code": "left_command",
              "modifiers": ["left_control", "left_option"]
            }
          ],
          "to_if_alone": [{ "key_code": "escape" }]
        }
      ]
    }
  ]
}
```

- [ ] **Step 4: Run the assertion to verify it passes**

Run the Step 1 block.
Expected: `PASS`.

- [ ] **Step 5: Add the copy-seed step to `keyboard_layer_install()`**

Append inside `keyboard_layer_install()`, after the aerospace symlink block:

```bash
  echo "  karabiner rule (copy-seed; enable it in the Karabiner GUI)"
  karabiner_rules="$HOME/.config/karabiner/assets/complex_modifications"
  mkdir -p "$karabiner_rules"
  if [ -e "$karabiner_rules/studio-hyper.json" ]; then
    echo "    studio-hyper.json already present — leaving it"
  else
    cp "$REPO_DIR/dotfiles/karabiner/studio-hyper.json" "$karabiner_rules/studio-hyper.json"
    echo "    ~> $karabiner_rules/studio-hyper.json"
  fi
```

- [ ] **Step 6: Verify shell still parses**

Run: `bash -n install.sh && shellcheck --severity=error install.sh && echo OK`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add dotfiles/karabiner/studio-hyper.json install.sh
git commit -m "feat(keyboard): karabiner Caps->Hyper/Esc rule + copy-seed step

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Manual setup checklist (GUI/license/secret steps)

**Files:**
- Modify: `install.sh` — append a checklist print to the end of `keyboard_layer_install()`.

**Interfaces:**
- Consumes: `keyboard_layer_install()`.
- Produces: terminal output only. No secrets prompted, echoed, or stored. No `defaults` writes (Homerow trigger and Raycast hotkeys are not verified as `defaults`-settable; Raycast's own onboarding handles the ⌘Space takeover and Spotlight, so those are documented rather than scripted).

- [ ] **Step 1: Write the failing assertion**

The checklist must mention each irreducible manual step. Assert the literal lines exist in `install.sh`:

```bash
grep -q 'Grant Accessibility' install.sh \
  && grep -q 'Activate Homerow' install.sh \
  && grep -q 'studio-hyper' install.sh \
  && grep -q 'Raycast' install.sh \
  && grep -q 'kept out of this repo' install.sh \
  && echo PASS || echo FAIL
```

- [ ] **Step 2: Run it to verify it fails**

Run the block above.
Expected: `FAIL` (checklist not written; note `studio-hyper` already appears from Task 3's copy-seed echo, but the other greps fail so the AND-chain prints `FAIL`).

- [ ] **Step 3: Add the checklist to `keyboard_layer_install()`**

Append inside `keyboard_layer_install()`, as the last block before the closing `}`:

```bash
  cat <<'CHECKLIST'

  ==> Manual steps (these cannot be scripted safely):
    1. Grant Accessibility permissions to AeroSpace, Homerow, and
       Karabiner-Elements:
         System Settings -> Privacy & Security -> Accessibility
       (All three need it; without it, shortcuts silently do nothing.)
    2. Activate Homerow with your license key. Your key is kept out of
       this repo by design — enter it directly in the Homerow app.
    3. Karabiner-Elements -> Complex Modifications -> Add rule ->
       enable "studio-hyper" (Caps Lock becomes Hyper on hold, Escape on tap).
    4. Open Raycast and complete onboarding: set its hotkey to Cmd+Space
       (Raycast offers to disable Spotlight's Cmd+Space for you), and
       disable Raycast's own window-management commands so they don't
       collide with AeroSpace.

  Keymap reference: see README (search "keyboard-first").
CHECKLIST
```

- [ ] **Step 4: Run the assertion to verify it passes**

Run the Step 1 block.
Expected: `PASS`.

- [ ] **Step 5: Verify shell still parses**

Run: `bash -n install.sh && shellcheck --severity=error install.sh && echo OK`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
git add install.sh
git commit -m "feat(keyboard): print manual setup checklist (permissions, license, rule enable)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: CI assertions

**Files:**
- Modify: `.github/workflows/macos.yml` — add a job/steps that assert the new wiring and validate the config files. Follow the existing step style (a named step running a shell block that `echo "::error::..."; exit 1` on failure).

**Interfaces:**
- Consumes: `install.sh`, `dotfiles/aerospace/aerospace.toml`, `dotfiles/karabiner/studio-hyper.json`.
- Produces: CI gate. No live `brew` calls (network-flaky; the tap requirement for AeroSpace makes a live cask check unreliable). Coverage is structural + parse only; runtime keybinding behavior is explicitly NOT covered by CI (manual acceptance only).

- [ ] **Step 1: Locate the insertion point**

Run: `grep -n 'jq is declared' .github/workflows/macos.yml`
Expected: a line number inside the macOS job's `steps:`. Add the new steps adjacent to it (same indentation).

- [ ] **Step 2: Add the CI steps**

Insert these steps into the macOS job in `.github/workflows/macos.yml` (match the surrounding indentation — steps are list items under `steps:`):

```yaml
      - name: --keyboard flag is wired (usage + dispatch)
        run: |
          grep -qE '^\s*--keyboard\)' install.sh || { echo "::error::--keyboard not in dispatch"; exit 1; }
          grep -q 'keyboard_layer_install' install.sh || { echo "::error::keyboard_layer_install missing"; exit 1; }
          grep -qE 'echo .*--keyboard' install.sh || { echo "::error::--keyboard not documented in usage()"; exit 1; }
          echo "--keyboard wired"

      - name: AeroSpace config is valid TOML with expected bindings
        run: |
          python3 -c "import tomllib; b=tomllib.load(open('dotfiles/aerospace/aerospace.toml','rb'))['mode']['main']['binding']; assert b['ctrl-alt-cmd-h']=='focus left'; assert b['ctrl-alt-cmd-1']=='workspace 1'; assert b['ctrl-alt-cmd-shift-1']=='move-node-to-workspace 1'; print('aerospace.toml ok')" \
            || { echo "::error::aerospace.toml invalid or missing expected bindings"; exit 1; }

      - name: Karabiner rule is valid JSON with the Hyper mapping
        run: |
          jq -e '.rules[0].manipulators[0] | (.from.key_code=="caps_lock") and (.to[0].key_code=="left_command") and (.to[0].modifiers==["left_control","left_option"]) and (.to_if_alone[0].key_code=="escape")' \
            dotfiles/karabiner/studio-hyper.json >/dev/null \
            || { echo "::error::studio-hyper.json invalid or missing Hyper mapping"; exit 1; }
          echo "studio-hyper.json ok"
```

- [ ] **Step 3: Validate the workflow YAML locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/macos.yml')); print('yaml ok')"`
Expected: `yaml ok` (if PyYAML missing, run `pip install pyyaml` first, or skip and rely on CI to catch YAML errors).

- [ ] **Step 4: Dry-run the assertion bodies locally (they must pass against the committed files)**

Run each `run:` block's body from the repo root.
Expected: `--keyboard wired`, `aerospace.toml ok`, `studio-hyper.json ok`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/macos.yml
git commit -m "ci: assert --keyboard wiring + validate aerospace/karabiner configs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `.gitignore` secret guard + README docs

**Files:**
- Modify: `.gitignore` (already contains `*.local`; add `secrets.env`).
- Modify: `README.md` — add a "keyboard-first" section.

**Interfaces:**
- Consumes: nothing.
- Produces: documentation + secret guard. `detect-secrets` pre-commit must still pass (no secret is being committed).

- [ ] **Step 1: Write the failing assertion**

```bash
grep -q 'secrets.env' .gitignore \
  && grep -qi 'keyboard-first' README.md \
  && grep -q '\-\-keyboard' README.md \
  && echo PASS || echo FAIL
```

- [ ] **Step 2: Run it to verify it fails**

Run the block above.
Expected: `FAIL`.

- [ ] **Step 3: Add the secret guard to `.gitignore`**

Append to `.gitignore` (below the existing `*.local` line):

```
secrets.env
```

- [ ] **Step 4: Add the README section**

Insert into `README.md` (after the "What's inside" section; pick the location that reads naturally alongside the other tool sections):

```markdown
## Keyboard-first layer (macOS, opt-in)

Run `./install.sh --keyboard` to install a four-layer keyboard-only stack.
It is opt-in: the default and `--full` installs do not touch it, because it
installs four GUI apps and remaps Caps Lock.

| Layer   | App                | Owns                                    |
|---------|--------------------|-----------------------------------------|
| Input   | Karabiner-Elements | Caps Lock → Hyper (held) / Escape (tap) |
| Launch  | Raycast            | App launch, search, clipboard, snippets |
| Windows | AeroSpace          | Tiling, focus, move, workspaces         |
| Click   | Homerow            | Click/scroll any element with no shortcut |

**Hyper** = `Ctrl+Alt+Cmd` (three modifiers; Shift is left free for "move"
variants). Caps Lock emits Hyper when held, Escape when tapped.

```
Hyper+H/J/K/L          focus window left/down/up/right
Hyper+Shift+H/J/K/L    move window
Hyper+1..9             switch workspace
Hyper+Shift+1..9       move window to workspace
Hyper+F                fullscreen
Hyper+Return           layout toggle (tiles/accordion)
Hyper+Space            Homerow click mode
Cmd+Space              Raycast
```

After running `--keyboard`, complete the manual steps the installer prints:
grant Accessibility permissions to the three apps, activate Homerow with your
license (kept out of this repo by design), enable the "studio-hyper" rule in
Karabiner, and finish Raycast onboarding (Cmd+Space, disable its window
commands). CI validates the config files and the installer wiring, but cannot
test runtime keybinding behavior — that is a manual acceptance step.
```

- [ ] **Step 5: Run the assertion to verify it passes**

Run the Step 1 block.
Expected: `PASS`.

- [ ] **Step 6: Confirm no secret leaked**

Run: `git diff --cached; git status`
Expected: no license key anywhere in the staged diff. (If `detect-secrets` runs as a pre-commit hook, it will also gate this on commit.)

- [ ] **Step 7: Commit**

```bash
git add .gitignore README.md
git commit -m "docs: keyboard-first layer README section + secrets.env gitignore guard

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Manual Acceptance (post-implementation, on a real macOS session)

Not automatable — run once by hand after `./install.sh --keyboard` and the manual steps:

- [ ] Caps tap emits Escape (test in nvim/text field); Caps hold acts as Hyper.
- [ ] `Hyper+H/J/K/L` moves window focus in AeroSpace.
- [ ] `Hyper+1..9` switches workspaces; `Hyper+Shift+1` moves the focused window.
- [ ] `Hyper+Space` activates Homerow click labels.
- [ ] `Cmd+Space` opens Raycast (not Spotlight).
- [ ] Re-running `./install.sh --keyboard` is idempotent (no duplicate work, existing configs backed up not clobbered).

## Future / Out of Scope

- Scripting Homerow's trigger key and Raycast's window hotkeys via `defaults` — only if a contributor verifies the exact keys take effect. Until then they stay manual.
- Windows equivalents (GlazeWM, PowerToys Run).
- Browser vim navigation.
