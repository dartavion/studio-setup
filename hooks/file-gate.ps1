# PreToolUse — prompts before new file creation; blocks if declined

$raw = $input | Out-String
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }

$filePath = $data.tool_input.file_path
if (-not $filePath) { exit 0 }

# Only gate new files — rewrites of existing files pass through
if (Test-Path $filePath) { exit 0 }

# Fail open if not running interactively
try { $null = $Host.UI.RawUI.WindowSize } catch { exit 0 }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("  create  $filePath")
[Console]::Error.Write("  allow? [enter / n]  ")

try {
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} catch { exit 0 }
[Console]::Error.WriteLine("")

if ($key.Character -eq 'n' -or $key.Character -eq 'N') {
    @{ decision = "block"; reason = "User declined creation of $filePath" } | ConvertTo-Json -Compress
}
