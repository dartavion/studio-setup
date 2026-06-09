# Stop hook — shows per-turn file receipt and prompts to open changed files in Neovim

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }

$sessionId = $data.session_id
$cwd       = $data.cwd
if (-not $sessionId) { exit 0 }

$editList = Join-Path $env:TEMP "claude-edits-$sessionId.txt"
if (-not (Test-Path $editList)) { exit 0 }

# Collect files that still exist
$files = Get-Content $editList -Encoding UTF8 | Where-Object { $_ -and (Test-Path $_) }
Remove-Item $editList -ErrorAction SilentlyContinue
if (-not $files -or $files.Count -eq 0) { exit 0 }

function Rel([string]$f) {
    if ($cwd -and $f.StartsWith($cwd)) { return $f.Substring($cwd.Length).TrimStart('\', '/') }
    return $f
}

[Console]::Error.WriteLine("")
[Console]::Error.WriteLine("━━ turn review ━━━━━━━━━━━━━━━━━━━━━━━━")
foreach ($f in $files) { [Console]::Error.WriteLine("  $(Rel $f)") }
[Console]::Error.WriteLine("────────────────────────────────────────")
if ($files.Count -gt 1) { [Console]::Error.WriteLine("  nvim: :bn / :bp  navigate  |  :bd  close buffer") }

# Require interactive terminal
try { $null = $Host.UI.RawUI.WindowSize } catch { exit 0 }

[Console]::Error.Write("  open in nvim? [enter / n]  ")
try { $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { exit 0 }
[Console]::Error.WriteLine("")
if ($key.Character -eq 'n' -or $key.Character -eq 'N') { exit 0 }

$pipe       = '\\.\pipe\nvim-claude'
$paneIdFile = "$env:TEMP\nvim-claude-pane-id"

function Test-PaneAlive($id) {
    try {
        $list = wezterm cli list --format json 2>$null | ConvertFrom-Json
        return $null -ne ($list | Where-Object { $_.pane_id -eq [int]$id })
    } catch { return $false }
}

function Test-NvimPipe {
    try {
        $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', 'nvim-claude',
            [System.IO.Pipes.PipeDirection]::InOut)
        $client.Connect(300)
        $client.Dispose()
        return $true
    } catch { return $false }
}

if ((Test-Path $paneIdFile) -and (Test-NvimPipe)) {
    $paneId = Get-Content $paneIdFile -ErrorAction SilentlyContinue
    if ($paneId -and (Test-PaneAlive $paneId)) {
        # Load in reverse so files[0] ends up active
        for ($i = $files.Count - 1; $i -ge 0; $i--) {
            & nvim --server $pipe --remote $files[$i] 2>$null
        }
        & nvim --server $pipe --remote-send "zz" 2>$null
        exit 0
    }
}

# Spawn new pane with all files in the arglist
$spawnArgs = @('cli', 'split-pane', '--', 'nvim', '--listen', $pipe) + @($files)
$id = & wezterm @spawnArgs 2>$null
if (-not $id) { exit 0 }
$id | Set-Content $paneIdFile
$waited = 0
while (-not (Test-NvimPipe) -and $waited -lt 20) { Start-Sleep -Milliseconds 100; $waited++ }
if (Test-NvimPipe) { & nvim --server $pipe --remote-send "zz" 2>$null }
