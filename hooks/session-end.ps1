# session-end hook — token usage and cost tracking
# Called with "stop" (per-turn) or "end" (session close)
# Rates are read from pricing.json in the same directory — edit that file to switch models.

param([string]$Mode = "end")

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput.Trim()) { exit 0 }

try   { $data = $rawInput | ConvertFrom-Json }
catch { exit 0 }

$sessionId      = $data.session_id
$transcriptPath = $data.transcript_path
$cwd            = $data.cwd

if (-not $sessionId) { exit 0 }

$tempFile = Join-Path $env:TEMP "claude-tokens-$sessionId.json"

function Format-Num([long]$n) {
    $r = ""
    while ($n -ge 1000) {
        $r = ",{0:D3}{1}" -f ($n % 1000), $r
        $n = [long][math]::Floor($n / 1000)
    }
    return "$n$r"
}

$pricing = Get-Content (Join-Path $PSScriptRoot "pricing.json") | ConvertFrom-Json
$rIn  = $pricing.rates_usd_per_mtok.input
$rOut = $pricing.rates_usd_per_mtok.output
$rCr  = $pricing.rates_usd_per_mtok.cache_read
$rCw5 = $pricing.rates_usd_per_mtok.cache_write_5m
$rCw1 = $pricing.rates_usd_per_mtok.cache_write_1h

function Calc-Cost([long]$inp, [long]$out, [long]$cr, [long]$cw5, [long]$cw1) {
    return ($inp * $rIn + $out * $rOut + $cr * $rCr + $cw5 * $rCw5 + $cw1 * $rCw1) / 1000000
}

# Reads transcript from $fromLine onward (1-based), parsing only new entries.
# Returns @{ totals = hashtable; total_lines = long }
function Sum-Usage([string]$path, [long]$fromLine = 0) {
    if (-not $path -or -not (Test-Path $path)) { return $null }
    $t = @{ input=0L; output=0L; cache_read=0L; cache_write_5m=0L; cache_write_1h=0L }
    $lineNum = 0L
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        $lineNum++
        if ($lineNum -le $fromLine) { continue }
        try {
            $entry = $line | ConvertFrom-Json
            if ($entry.type -eq "assistant" -and $entry.message -and $entry.message.usage) {
                $u = $entry.message.usage
                $t.input      += [long]$(if ($u.input_tokens)            { $u.input_tokens }            else { 0 })
                $t.output     += [long]$(if ($u.output_tokens)           { $u.output_tokens }           else { 0 })
                $t.cache_read += [long]$(if ($u.cache_read_input_tokens) { $u.cache_read_input_tokens } else { 0 })
                if ($u.cache_creation) {
                    $t.cache_write_5m += [long]$(if ($u.cache_creation.ephemeral_5m_input_tokens) { $u.cache_creation.ephemeral_5m_input_tokens } else { 0 })
                    $t.cache_write_1h += [long]$(if ($u.cache_creation.ephemeral_1h_input_tokens) { $u.cache_creation.ephemeral_1h_input_tokens } else { 0 })
                }
            }
        } catch {}
    }
    return @{ totals = $t; total_lines = $lineNum }
}

function Find-Transcript {
    if ($transcriptPath -and (Test-Path $transcriptPath)) { return $transcriptPath }
    return Get-ChildItem "$HOME\.claude\projects" -Recurse -Filter "$sessionId.jsonl" `
        -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}

if ($Mode -eq "stop") {
    $tpath = Find-Transcript
    if (-not $tpath) { exit 0 }

    $prevIn = 0L; $prevOut = 0L; $prevCr = 0L; $prevCw5 = 0L; $prevCw1 = 0L; $prevLines = 0L
    if (Test-Path $tempFile) {
        $prev      = Get-Content $tempFile -Raw | ConvertFrom-Json
        $prevIn    = [long]$prev.input
        $prevOut   = [long]$prev.output
        $prevCr    = [long]$prev.cache_read
        $prevCw5   = [long]$prev.cache_write_5m
        $prevCw1   = [long]$prev.cache_write_1h
        $prevLines = [long]$prev.lines_read
    }

    $result = Sum-Usage $tpath $prevLines
    if (-not $result) { exit 0 }

    $d   = $result.totals
    $inp = $prevIn  + $d.input
    $out = $prevOut + $d.output
    $cr  = $prevCr  + $d.cache_read
    $cw5 = $prevCw5 + $d.cache_write_5m
    $cw1 = $prevCw1 + $d.cache_write_1h

    [PSCustomObject]@{
        input          = $inp
        output         = $out
        cache_read     = $cr
        cache_write_5m = $cw5
        cache_write_1h = $cw1
        lines_read     = $result.total_lines
    } | ConvertTo-Json -Compress | Set-Content $tempFile -Encoding UTF8

    $cw   = $cw5 + $cw1
    $cost = Calc-Cost $inp $out $cr $cw5 $cw1
    [Console]::Error.WriteLine("▸ tokens  in={0,-9} out={1,-8} cr={2,-10} cw={3,-10}  ~`${4:F4}" -f `
        (Format-Num $inp), (Format-Num $out), (Format-Num $cr), (Format-Num $cw), $cost)

} elseif ($Mode -eq "end") {
    $inp = 0L; $out = 0L; $cr = 0L; $cw5 = 0L; $cw1 = 0L

    if (Test-Path $tempFile) {
        $prev = Get-Content $tempFile -Raw | ConvertFrom-Json
        $inp  = [long]$prev.input
        $out  = [long]$prev.output
        $cr   = [long]$prev.cache_read
        $cw5  = [long]$prev.cache_write_5m
        $cw1  = [long]$prev.cache_write_1h
    } else {
        $tpath  = Find-Transcript
        $result = Sum-Usage $tpath 0
        if (-not $result) { exit 0 }
        $d = $result.totals
        $inp = $d.input; $out = $d.output; $cr = $d.cache_read
        $cw5 = $d.cache_write_5m; $cw1 = $d.cache_write_1h
    }

    $cw        = $cw5 + $cw1
    $cost      = Calc-Cost $inp $out $cr $cw5 $cw1
    $project   = Split-Path -Leaf $(if ($cwd) { $cwd } else { (Get-Location).Path })
    $branch    = git -C $(if ($cwd) { $cwd } else { "." }) branch --show-current 2>$null
    $branchStr = if ($branch) { " ($branch)" } else { "" }

    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("━━ session end ━━━━━━━━━━━━━━━━━━━━━━━━━")
    [Console]::Error.WriteLine("  {0,-10} {1}"    -f "project",  "$project$branchStr")
    [Console]::Error.WriteLine("  {0,-10} {1,13}" -f "input",    (Format-Num $inp))
    [Console]::Error.WriteLine("  {0,-10} {1,13}" -f "output",   (Format-Num $out))
    [Console]::Error.WriteLine("  {0,-10} {1,13}" -f "cache rd", (Format-Num $cr))
    [Console]::Error.WriteLine("  {0,-10} {1,13}" -f "cache wr", (Format-Num $cw))
    [Console]::Error.WriteLine("  ───────────────────────────────────────")
    [Console]::Error.WriteLine("  {0,-10} {1,13}" -f "est. cost", ("`${0:F4}" -f $cost))
    [Console]::Error.WriteLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    [Console]::Error.WriteLine("  API list rates: sonnet-4.6  (not seat cost)")

    $logFile = Join-Path $HOME ".claude\token-log.jsonl"
    [PSCustomObject]@{
        input          = $inp
        output         = $out
        cache_read     = $cr
        cache_write_5m = $cw5
        cache_write_1h = $cw1
        session_id     = $sessionId
        project        = $project
        branch         = $(if ($branch) { $branch } else { "" })
        ended_at       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        cost_usd       = [math]::Round($cost, 4)
    } | ConvertTo-Json -Compress | Add-Content $logFile -Encoding UTF8

    Remove-Item $tempFile -ErrorAction SilentlyContinue
}
