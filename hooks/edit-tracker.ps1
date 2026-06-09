# PostToolUse — silently records each edited file path for per-turn review

$raw = $input | Out-String
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }

$sessionId = $data.session_id
$filePath  = $data.tool_input.file_path
if (-not $sessionId -or -not $filePath) { exit 0 }

$editList = Join-Path $env:TEMP "claude-edits-$sessionId.txt"
$existing = if (Test-Path $editList) { Get-Content $editList } else { @() }
if ($filePath -notin $existing) {
    Add-Content $editList $filePath -Encoding UTF8
}
