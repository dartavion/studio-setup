# SessionStart hook — injects live git context so Claude never starts cold
# Requires: git, gh

$branch = git branch --show-current 2>$null
if (-not $branch) { exit 0 }

$msg = "Branch: $branch"

$recent = git log --oneline -5 2>$null
if ($recent) { $msg += "`nRecent commits:`n$($recent -join "`n")" }

$status = git status --short 2>$null
if ($status) { $msg += "`nUncommitted changes:`n$($status -join "`n")" }

$prJob = Start-Job -ScriptBlock { gh pr list --json number,title --limit 5 2>$null }
$prJson = if (Wait-Job $prJob -Timeout 5) { Receive-Job $prJob } else { $null }
Remove-Job $prJob -Force 2>$null
if ($prJson) {
    $prs = ($prJson | ConvertFrom-Json) | ForEach-Object { "#$($_.number) $($_.title)" }
    if ($prs) { $msg += "`nOpen PRs:`n$($prs -join "`n")" }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
@{ systemMessage = $msg } | ConvertTo-Json -Compress
