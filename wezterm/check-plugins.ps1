# Windows twin of check-plugins.sh — verify the wezterm plugins cloned on this
# machine still match the vetted SHAs in wezterm/plugins.lock. wezterm.plugin.require
# can't pin to a ref, so this is drift / tamper detection, NOT pinning. Run it
# periodically, especially after wezterm.plugin.update_all().
#
#   OK     — cached clone HEAD == locked SHA
#   DRIFT  — clone moved (an update or tamper); review before trusting
#   ABSENT — not cloned yet (will clone on next WezTerm launch, then re-run this)
#
# Exit 0 if everything matches/absent; exit 1 if any DRIFT is found.

$ErrorActionPreference = "Stop"

$lock = Join-Path $PSScriptRoot "plugins.lock"
if (-not (Test-Path $lock)) { Write-Error "no plugins.lock next to this script"; exit 1 }

# Plugin cache: WezTerm stores clones in <runtime dir>/plugins. On Windows that's
# %APPDATA%\wezterm\plugins; fall back to the XDG-style path; allow an override.
$candidates = @(
    $env:WEZTERM_PLUGIN_DIR,
    (Join-Path $env:APPDATA "wezterm\plugins"),
    (Join-Path $HOME ".local\share\wezterm\plugins")
) | Where-Object { $_ }
$cache = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

# Map origin URL -> cached clone dir
$clone = @{}
if ($cache) {
    Get-ChildItem -Path $cache -Directory | ForEach-Object {
        if (Test-Path (Join-Path $_.FullName ".git")) {
            $u = (git -C $_.FullName config --get remote.origin.url 2>$null)
            if ($u) { $clone[$u.Trim()] = $_.FullName }
        }
    }
}

$locked = (Get-Content $lock -Raw | ConvertFrom-Json).plugins
$drift = 0
foreach ($p in $locked.PSObject.Properties) {
    $url = $p.Name; $want = $p.Value
    $dir = $clone[$url]
    if (-not $dir) {
        Write-Host ("  ABSENT {0}" -f $url) -ForegroundColor DarkGray
        continue
    }
    $have = (git -C $dir rev-parse HEAD 2>$null)
    if ($have -eq $want) {
        Write-Host ("  OK     {0}" -f $url) -ForegroundColor Green
    } else {
        Write-Host ("  DRIFT  {0}" -f $url) -ForegroundColor Yellow
        Write-Host ("         locked {0}" -f $want)
        Write-Host ("         cached {0}" -f $have)
        $drift = 1
    }
}

Write-Host ""
if ($drift -ne 0) {
    Write-Host "Drift found. Review the upstream changes; if trusted, regenerate plugins.lock."
    exit 1
}
Write-Host "All cloned plugins match plugins.lock."
