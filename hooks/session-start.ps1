# SessionStart hook — injects live git context so Claude never starts cold
# Requires: git, gh

$inputJson = if ($Input) { $Input | Out-String } else { $null }
$dir = "."
if ($inputJson) {
    try {
        $parsed = $inputJson | ConvertFrom-Json
        if ($parsed.cwd) { $dir = $parsed.cwd }
    } catch {}
}

# Spawn a new WezTerm workspace if we start a session in a different repo inside WezTerm
if ($env:WEZTERM_PANE) {
    $currentWorkspace = wezterm cli get-workspace 2>$null
    $gitToplevel = git -C $dir rev-parse --show-toplevel 2>$null
    $repoName = if ($gitToplevel) { Split-Path $gitToplevel -Leaf } else { Split-Path $dir -Leaf }
    if ($repoName -and $currentWorkspace -ne $repoName) {
        wezterm cli spawn --new-window --workspace $repoName --cwd $dir 2>$null | Out-Null
    }
}

$branch = git -C $dir branch --show-current 2>$null
if (-not $branch) { exit 0 }

$msg = "Branch: $branch"

$recent = git -C $dir log --oneline -5 2>$null
if ($recent) { $msg += "`nRecent commits:`n$($recent -join "`n")" }

$status = git -C $dir status --short 2>$null
if ($status) { $msg += "`nUncommitted changes:`n$($status -join "`n")" }

$prJob = Start-Job -ScriptBlock { param($d) gh -C $d pr list --json number,title --limit 5 2>$null } -ArgumentList $dir
$prJson = if (Wait-Job $prJob -Timeout 5) { Receive-Job $prJob } else { $null }
Remove-Job $prJob -Force 2>$null
if ($prJson) {
    $prs = ($prJson | ConvertFrom-Json) | ForEach-Object { "#$($_.number) $($_.title)" }
    if ($prs) { $msg += "`nOpen PRs:`n$($prs -join "`n")" }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
@{ systemMessage = $msg } | ConvertTo-Json -Compress
