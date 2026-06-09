## PowerShell profile — Catppuccin Mocha palette
## Sourced by $PROFILE (PowerShell 7 / pwsh)
## Machine-specific overrides go in $PROFILE.local (never committed)

## ── PSReadLine (autosuggestions + history nav) ───────────────────────────────

if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineKeyHandler -Key Tab            -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow        -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow      -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
}

## ── modern CLI replacements ──────────────────────────────────────────────────

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls   { eza --icons --group-directories-first @args }
    function ll   { eza -la --icons --group-directories-first --git @args }
    function la   { eza -a --icons --group-directories-first @args }
    function tree { eza --tree --icons @args }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { bat --style=plain --pager=never @args }
    $env:BAT_THEME = "Catppuccin Mocha"
}

# fzf
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
    $env:FZF_DEFAULT_OPTS = @"
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
"@
    # PSFzf key bindings (Ctrl+T = files, Ctrl+R = history)
    if (Get-Module -ListAvailable -Name PSFzf) {
        Import-Module PSFzf
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    }
}

# zoxide (better cd)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

## ── git aliases (functions so they pass args naturally) ──────────────────────

function g   { git @args }
function gs  { git status }
function ga  { git add @args }
function gc  { git commit @args }
function gp  { git push @args }
function gpl { git pull @args }
function gd  { git diff @args }
function gco { git checkout @args }
function gb  { git branch @args }
function gl  { git log --oneline --graph --decorate --all @args }

## ── dev shortcuts ────────────────────────────────────────────────────────────

function nv  { nvim @args }
function v   { nvim @args }
function c   { claude @args }

## ── machine-specific overrides ───────────────────────────────────────────────

$LocalProfile = Join-Path (Split-Path $PROFILE) "profile.local.ps1"
if (Test-Path $LocalProfile) { . $LocalProfile }

## ── prompt ───────────────────────────────────────────────────────────────────

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
