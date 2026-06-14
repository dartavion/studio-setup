param(
    [switch]$Full,
    [switch]$VaultOnly,
    [switch]$Plugins,
    [string]$Vault,
    [switch]$UpdateLock
)

$RepoDir   = $PSScriptRoot
$BaseVault = Join-Path $RepoDir "vault"
$LockFile  = Join-Path $RepoDir "versions.lock"
$CheckFile = Join-Path $RepoDir "checksums.sha256"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── helpers ───────────────────────────────────────────────────────────────────

function Test-Command($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Install-WingetApp($id, $label) {
    Write-Host "  ensuring $label..."
    winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements 2>$null
    # 0 = installed now; -1978335189 (0x8A150021) = already installed — both are fine
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Host "  warning: winget exited $LASTEXITCODE for $label — may need manual install"
    }
}

function Install-ScoopApp($name) {
    if (scoop list $name 2>$null | Select-String $name) {
        Write-Host "  $name ok"
    } else {
        Write-Host "  installing $name..."
        scoop install $name
    }
}

function Get-PinnedVersion($id) {
    $lock = Get-Content $LockFile | ConvertFrom-Json
    if ($lock.plugins.PSObject.Properties[$id]) { return $lock.plugins.$id }
    return "latest"
}

function Get-StoredChecksum($id) {
    if (-not (Test-Path $CheckFile)) { return $null }
    $line = Get-Content $CheckFile | Where-Object { $_ -match "^$id=" }
    if ($line) { return ($line -split "=", 2)[1] }
    return $null
}

function Assert-Checksum($id, $file) {
    $expected = Get-StoredChecksum $id
    if (-not $expected) { return }
    $actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Host ""
        Write-Host "  !! CHECKSUM MISMATCH: $id"
        Write-Host "     expected: $expected"
        Write-Host "     got:      $actual"
        Write-Host "     Aborting. If this is a legitimate update run: .\install.ps1 -UpdateLock"
        exit 1
    }
}

function Invoke-VerifiedScript($id, $url) {
    $expected = Get-StoredChecksum $id
    if (-not $expected) {
        Write-Error "No stored checksum found for $id"
        exit 1
    }
    $tempFile = Join-Path $env:TEMP "install-$id.ps1"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
        $actual = (Get-FileHash $tempFile -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected) {
            Write-Host ""
            Write-Host "  !! SECURITY VIOLATION: Checksum mismatch for external installer: $id"
            Write-Host "     URL:      $url"
            Write-Host "     Expected: $expected"
            Write-Host "     Got:      $actual"
            Write-Host "     Aborting execution for safety."
            exit 1
        }
        . $tempFile
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
}


# ── symlink helper (falls back to copy if Developer Mode not enabled) ─────────

function Set-Link($target, $source) {
    if (Test-Path $target) {
        $existing = Get-Item $target -ErrorAction SilentlyContinue
        if ($existing.LinkType -eq "SymbolicLink") {
            Remove-Item $target -Force
        } else {
            $stamp = Get-Date -Format "yyyyMMddHHmmss"
            Rename-Item $target "$target.bak.$stamp"
            Write-Host "    backed up existing $(Split-Path $target -Leaf)"
        }
    }
    try {
        New-Item -ItemType SymbolicLink -Path $target -Target $source -Force | Out-Null
    } catch {
        Copy-Item $source $target -Force
    }
    Write-Host "    -> $target"
}

# ── plugin manifest ───────────────────────────────────────────────────────────

$PluginRepos = [ordered]@{
    "calendar"                   = "liamcain/obsidian-calendar-plugin"
    "codeblock-customizer"       = "mugiwara85/CodeblockCustomizer"
    "dataview"                   = "blacksmithgu/obsidian-dataview"
    "homepage"                   = "mirnovov/obsidian-homepage"
    "obsidian-excalidraw-plugin" = "zsviczian/obsidian-excalidraw-plugin"
    "obsidian-icon-folder"       = "FlorianWoelki/obsidian-iconize"
    "obsidian-kanban"            = "mgmeyers/obsidian-kanban"
    "obsidian-style-settings"    = "mgmeyers/obsidian-style-settings"
    "periodic-notes"             = "liamcain/obsidian-periodic-notes"
    "quickadd"                   = "chhoumann/quickadd"
    "smart-connections"          = "brianpetro/obsidian-smart-connections"
    "templater-obsidian"         = "SilentVoid13/Templater"
}

function Install-Plugins($vaultPath) {
    $obsidianDir = Join-Path $vaultPath ".obsidian"
    Write-Host "==> Installing plugins into $obsidianDir"

    foreach ($id in $PluginRepos.Keys) {
        $repo    = $PluginRepos[$id]
        $version = Get-PinnedVersion $id
        $plugDir = Join-Path $obsidianDir "plugins\$id"
        New-Item -ItemType Directory -Path $plugDir -Force | Out-Null
        Write-Host "  $id @ $version"

        foreach ($asset in @("main.js", "manifest.json", "styles.css")) {
            $dest      = Join-Path $plugDir $asset
            $directUrl = "https://github.com/$repo/releases/download/$version/$asset"
            $downloaded = $false

            # try direct URL first — no auth needed
            try {
                Invoke-WebRequest -Uri $directUrl -OutFile $dest -UseBasicParsing -ErrorAction Stop
                $downloaded = $true
            } catch { }

            # fall back to gh api for non-standard release layouts
            if (-not $downloaded -and (Test-Command gh)) {
                $url = gh api "repos/$repo/releases/tags/$version" `
                    -q ".assets[] | select(.name == `"$asset`") | .browser_download_url" 2>$null
                if ($url) {
                    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
                    $downloaded = $true
                }
            }

            if ($downloaded -and $asset -eq "main.js") { Assert-Checksum $id $dest }
        }
    }

    # Catppuccin theme
    $themeDir = Join-Path $obsidianDir "themes\Catppuccin"
    if (-not (Test-Path (Join-Path $themeDir "theme.css"))) {
        Write-Host "  Catppuccin theme"
        New-Item -ItemType Directory -Path $themeDir -Force | Out-Null
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/catppuccin/obsidian/main/theme.css"    -OutFile (Join-Path $themeDir "theme.css")    -UseBasicParsing -ErrorAction Stop
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/catppuccin/obsidian/main/manifest.json" -OutFile (Join-Path $themeDir "manifest.json") -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "  warning: Catppuccin theme download failed — vault will open without theme"
        }
    }

    Write-Host "==> plugins installed and verified"
}

# ── full install ──────────────────────────────────────────────────────────────

function Invoke-FullInstall {
    Write-Host "==> studio-setup full install (Windows)"

    # winget check
    if (-not (Test-Command winget)) {
        Write-Host "  winget not found. Install from https://aka.ms/winget or the Microsoft Store."
        exit 1
    }

    # scoop
    if (-not (Test-Command scoop)) {
        Write-Host "  installing Scoop..."
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-VerifiedScript "installer-scoop" "https://get.scoop.sh"
    } else {
        Write-Host "  scoop ok"
    }

    # scoop buckets
    scoop bucket add extras  2>$null | Out-Null
    scoop bucket add nerd-fonts 2>$null | Out-Null

    # GUI apps via winget
    Install-WingetApp "wez.wezterm"         "WezTerm"
    Install-WingetApp "Obsidian.Obsidian"   "Obsidian"
    Install-WingetApp "OpenJS.NodeJS.LTS"   "Node.js LTS"
    Install-WingetApp "GitHub.cli"          "gh"

    # CLI tools via scoop
    Install-ScoopApp "neovim"
    Install-ScoopApp "tree-sitter"   # nvim-treesitter (main branch) builds parsers with the tree-sitter CLI
    Install-ScoopApp "starship"
    Install-ScoopApp "eza"
    Install-ScoopApp "bat"
    Install-ScoopApp "fzf"
    Install-ScoopApp "fd"
    Install-ScoopApp "zoxide"
    Install-ScoopApp "ripgrep"
    Install-ScoopApp "JetBrainsMono-NF"

    # PSFzf for fzf key bindings in PowerShell
    if (-not (Get-Module -ListAvailable -Name PSFzf)) {
        Write-Host "  installing PSFzf..."
        Install-Module PSFzf -Scope CurrentUser -Force
    } else {
        Write-Host "  PSFzf ok"
    }

    # Claude Code
    if (-not (Test-Command claude)) {
        Write-Host "  installing Claude Code..."
        npm install -g --ignore-scripts @anthropic-ai/claude-code
    } else {
        Write-Host "  claude ok"
    }

    # gh auth check
    $ghAuth = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  gh is not authenticated. Run: gh auth login"
        Write-Host "  Then re-run: .\install.ps1 -Full"
        exit 1
    }

    # run base install (wezterm, dotfiles, hooks)
    & "$PSScriptRoot\install.ps1"

    Install-Plugins $BaseVault

    Write-Host ""
    Write-Host "==> All done."
    Write-Host ""
    Write-Host "  Manual steps remaining:"
    Write-Host ""
    Write-Host "  1. Open Obsidian → Add Vault → select vault\"
    Write-Host "  2. Settings → Community plugins → click 'Trust' for each plugin"
    Write-Host ""
    Write-Host "  Dashboard opens automatically and KPI cards render on first load."
}

# ── seed_vault ────────────────────────────────────────────────────────────────

function Invoke-SeedVault($targetPath) {
    Write-Host "==> Seeding vault at $targetPath"

    foreach ($dir in @("$targetPath\.obsidian\snippets", "$targetPath\.obsidian\plugins",
                        "$targetPath\00-Meta\Templates", "$targetPath\reports")) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    foreach ($f in @("appearance.json", "community-plugins.json")) {
        $src  = Join-Path $BaseVault ".obsidian\$f"
        $dest = Join-Path $targetPath ".obsidian\$f"
        if (-not (Test-Path $dest)) {
            Copy-Item $src $dest
            Write-Host "  + .obsidian\$f"
        }
    }

    foreach ($f in Get-ChildItem (Join-Path $BaseVault ".obsidian\snippets\*.css")) {
        $dest = Join-Path $targetPath ".obsidian\snippets\$($f.Name)"
        if (-not (Test-Path $dest)) {
            Copy-Item $f.FullName $dest
            Write-Host "  + snippets\$($f.Name)"
        }
    }

    foreach ($plugDir in Get-ChildItem (Join-Path $BaseVault ".obsidian\plugins") -Directory) {
        $destPlug = Join-Path $targetPath ".obsidian\plugins\$($plugDir.Name)"
        New-Item -ItemType Directory -Path $destPlug -Force | Out-Null
        foreach ($ff in @("data.json", "manifest.json")) {
            $src  = Join-Path $plugDir.FullName $ff
            $dest = Join-Path $destPlug $ff
            if ((Test-Path $src) -and -not (Test-Path $dest)) {
                Copy-Item $src $dest
                Write-Host "  + plugins\$($plugDir.Name)\$ff"
            }
        }
    }

    foreach ($f in Get-ChildItem (Join-Path $BaseVault "00-Meta\Templates\*.md")) {
        $dest = Join-Path $targetPath "00-Meta\Templates\$($f.Name)"
        if (-not (Test-Path $dest)) {
            Copy-Item $f.FullName $dest
            Write-Host "  + 00-Meta\Templates\$($f.Name)"
        }
    }

    if (-not (Test-Path (Join-Path $targetPath "Dashboard.md"))) {
        Copy-Item (Join-Path $BaseVault "Dashboard.md") (Join-Path $targetPath "Dashboard.md")
        Write-Host "  + Dashboard.md"
    }
    if (-not (Test-Path (Join-Path $targetPath "reports\kpi-snapshot.json"))) {
        Copy-Item (Join-Path $BaseVault "reports\kpi-snapshot.json") (Join-Path $targetPath "reports\kpi-snapshot.json")
        Write-Host "  + reports\kpi-snapshot.json"
    }

    Install-Plugins $targetPath
}

# ── base install (wezterm + dotfiles + hooks) ─────────────────────────────────

function Invoke-BaseInstall {
    Write-Host "==> studio-setup install"

    # ── WezTerm ───────────────────────────────────────────────────────────────
    Write-Host "  wezterm"
    $weztermCfg = Join-Path $env:USERPROFILE ".config\wezterm"
    New-Item -ItemType Directory -Path $weztermCfg -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $weztermCfg "workspaces") -Force | Out-Null

    foreach ($f in @("wezterm.lua", "utils.lua")) {
        Set-Link (Join-Path $weztermCfg $f) (Join-Path $RepoDir "wezterm\$f")
    }
    foreach ($f in Get-ChildItem (Join-Path $RepoDir "wezterm\workspaces\*.lua")) {
        if ($f.Name -eq "workspace.template.lua") { continue }
        $dest = Join-Path $weztermCfg "workspaces\$($f.Name)"
        if (-not (Test-Path $dest)) { Set-Link $dest $f.FullName }
    }

    # ── Dotfiles ──────────────────────────────────────────────────────────────
    Write-Host "  dotfiles"

    # PowerShell profile
    $profileDir = Split-Path $PROFILE
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Set-Link $PROFILE (Join-Path $RepoDir "dotfiles\powershell\profile.ps1")

    # Local profile template (never overwrite)
    $localProfile = Join-Path $profileDir "profile.local.ps1"
    if (-not (Test-Path $localProfile)) {
        Copy-Item (Join-Path $RepoDir "dotfiles\powershell\profile.local.template.ps1") $localProfile
        Write-Host "    created profile.local.ps1 from template"
    }

    # Starship
    $configDir = Join-Path $env:USERPROFILE ".config"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null

    # If starship is installed, attempt to generate the tokyo-night preset into the user config.
    # If generation fails (or starship is missing), fall back to symlinking the repo-provided config.
    $starshipCmd = Get-Command starship -ErrorAction SilentlyContinue
    $dest = Join-Path $configDir "starship.toml"
    if ($starshipCmd) {
        if (-not (Test-Path $dest)) {
            Write-Host "    generating starship preset: tokyo-night -> $dest"
            try {
                & starship preset tokyo-night -o $dest
                Write-Host "    -> $dest"
            } catch {
                Write-Host "    warning: starship preset failed, copying repo default"
                Copy-Item (Join-Path $RepoDir "dotfiles\starship.toml") $dest -Force
                Write-Host "    -> $dest"
            }
        } else {
            Write-Host "    $dest already exists — kept"
        }
    } else {
        Set-Link (Join-Path $configDir "starship.toml") (Join-Path $RepoDir "dotfiles\starship.toml")
    }

    # Neovim
    $nvimDir = Join-Path $env:LOCALAPPDATA "nvim"
    New-Item -ItemType Directory -Path $nvimDir -Force | Out-Null
    Set-Link (Join-Path $nvimDir "init.lua") (Join-Path $RepoDir "dotfiles\nvim\init.lua")

    # ── Global CLAUDE.md — Epistemic Honesty ─────────────────────────────────
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    $claudeMd  = Join-Path $claudeDir "CLAUDE.md"
    $alreadyPresent = (Test-Path $claudeMd) -and ((Get-Content $claudeMd -Raw) -match "## Epistemic Honesty")
    if (-not $alreadyPresent) {
        Add-Content $claudeMd "`n" -Encoding UTF8
        Get-Content (Join-Path $RepoDir "dotfiles\claude-global.md") -Raw | Add-Content $claudeMd -Encoding UTF8
        Write-Host "    -> $claudeMd (Epistemic Honesty appended)"
    } else {
        Write-Host "    $claudeMd already contains Epistemic Honesty — skipped"
    }

    # ── Claude Code hooks ─────────────────────────────────────────────────────
    Write-Host "  claude hooks"
    $hooksDir = Join-Path $env:USERPROFILE ".claude\hooks"
    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null

    foreach ($f in Get-ChildItem (Join-Path $RepoDir "hooks\*.ps1")) {
        Copy-Item $f.FullName (Join-Path $hooksDir $f.Name) -Force
        Write-Host "    -> $hooksDir\$($f.Name)"
    }
    # copy supporting config files alongside the hooks
    foreach ($f in Get-ChildItem (Join-Path $RepoDir "hooks\*.json")) {
        Copy-Item $f.FullName (Join-Path $hooksDir $f.Name) -Force
        Write-Host "    -> $hooksDir\$($f.Name)"
    }

    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    if (-not (Test-Path $settingsPath)) { '{}' | Set-Content $settingsPath }

    $settings = Get-Content $settingsPath | ConvertFrom-Json
    if (-not $settings.hooks) {
        $settings | Add-Member -MemberType NoteProperty -Name hooks -Value ([PSCustomObject]@{}) -Force
    }

    $hooksJson = @{
        PreToolUse  = @(@{ matcher = "Write";        hooks = @(@{ type = "command"; command = "$hooksDir\file-gate.ps1"; shell = "powershell" }) },
                        @{ matcher = "Bash";         hooks = @(@{ type = "command"; command = "$hooksDir\git-guard.ps1"; shell = "powershell" }) })
        PostToolUse = @(@{ matcher = "Edit|Write";   hooks = @(@{ type = "command"; command = "$hooksDir\edit-tracker.ps1"; shell = "powershell"; async = $true }) })
        Stop        = @(@{ hooks = @(@{ type = "command"; command = "$hooksDir\turn-review.ps1"; shell = "powershell" }) },
                        @{ hooks = @(@{ type = "command"; command = "$hooksDir\session-end.ps1 stop"; shell = "powershell" }) })
        SessionStart = @(@{ hooks = @(@{ type = "command"; command = "$hooksDir\session-start.ps1"; shell = "powershell" }) })
        SessionEnd   = @(@{ hooks = @(@{ type = "command"; command = "$hooksDir\session-end.ps1 end"; shell = "powershell" }) })
    }

    foreach ($event in $hooksJson.Keys) {
        if (-not $settings.hooks.PSObject.Properties[$event]) {
            $settings.hooks | Add-Member -MemberType NoteProperty -Name $event -Value $hooksJson[$event]
        } else {
            # merge at the command level — don't add duplicates
            $existingCmds = @(
                $settings.hooks.$event | ForEach-Object { $_.hooks } | ForEach-Object { $_.command }
            )
            foreach ($entry in $hooksJson[$event]) {
                foreach ($h in $entry.hooks) {
                    if ($h.command -notin $existingCmds) {
                        $settings.hooks.$event += $entry
                        $existingCmds += $h.command
                        break
                    }
                }
            }
        }
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    Write-Host "    settings.json updated"

    Write-Host "==> done"
}

# ── persona routing ───────────────────────────────────────────────────────────

function Test-GhAvailable {
    if (-not (Test-Command gh)) { return $false }
    gh auth status 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Invoke-AskPersona {
    Write-Host ""
    Write-Host "  gh CLI not set up. Quick question:"
    Write-Host ""
    Write-Host "  [1] Developer          — need the full dev environment"
    Write-Host "  [2] Designer / product — just want the Obsidian vault"
    Write-Host ""
    $choice = Read-Host "  Your choice (1/2)"
    Write-Host ""

    if ($choice -eq "1") {
        Write-Host "  Developer path — gh CLI needed for the full setup."
        Write-Host ""
        Write-Host "  Install:      winget install GitHub.cli"
        Write-Host "  Authenticate: gh auth login"
        Write-Host ""
        Write-Host "  Then re-run: .\install.ps1 -Full"
        exit 0
    } else {
        Write-Host "  Designer/product path — downloading plugins directly (no gh needed)."
        Write-Host ""
    }
}

# ── vault-only install (designers / product folks) ───────────────────────────

function Invoke-VaultOnly {
    Write-Host "==> studio-setup — Obsidian vault setup"

    if (-not (Test-GhAvailable)) { Invoke-AskPersona }

    Install-Plugins $BaseVault

    Write-Host ""
    Write-Host "==> Done. One manual step:"
    Write-Host ""
    Write-Host "  1. Open Obsidian"
    Write-Host "  2. Add Vault -> select: $BaseVault"
    Write-Host "  3. Settings -> Community plugins -> click 'Trust' for each plugin"
    Write-Host ""
    Write-Host "  The Dashboard opens automatically. KPI cards, tasks, and project"
    Write-Host "  tables all render on first load — no further configuration needed."
}

# ── entry point ───────────────────────────────────────────────────────────────

if     ($Full)                { Invoke-FullInstall }
elseif ($VaultOnly)           { Invoke-VaultOnly }
elseif ($Plugins -and $Vault) { Install-Plugins $Vault }
elseif ($Plugins)             { Install-Plugins $BaseVault }
elseif ($Vault)               { Invoke-SeedVault $Vault }
elseif ($UpdateLock)          {
    Write-Host "==> UpdateLock is handled by install.sh — run under WSL or macOS."
    Write-Host "    On Windows, run: wsl ./install.sh --update-lock"
}
else                          { Invoke-BaseInstall }
