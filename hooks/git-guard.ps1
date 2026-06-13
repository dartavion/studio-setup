# PreToolUse(Bash) — block blanket git staging (Windows twin of git-guard.sh).
#
# `git add -A` / `git add --all` / `git add .` stage everything, which can sweep
# unrelated uncommitted work into a commit. This guard denies those and tells the
# caller to stage specific paths instead. Specific-path adds pass through.

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
if (-not $raw.Trim()) { exit 0 }

try   { $data = $raw | ConvertFrom-Json } catch { exit 0 }
$cmd = $data.tool_input.command
if (-not $cmd) { exit 0 }

# `git add` with -A, --all, or a bare "." pathspec, but only at a COMMAND boundary
# (line start, or after ; && |) so the pattern inside a quoted -m "..." message doesn't
# false-trigger. `cd x; git add -A` still caught; `git add <path>` passes. (?m) so ^/$
# match per line in multi-line commands.
if ($cmd -match '(?m)(^|[;&|])\s*git\s+add\s+([^&|;]*\s)?(-A|--all|\.)(\s|$)') {
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = "PreToolUse"
            permissionDecision       = "deny"
            permissionDecisionReason = "Blocked blanket git staging: ``$cmd``. Stage specific paths instead (git add <path> ...) and confirm no unrelated WIP is included."
        }
    }
    $out | ConvertTo-Json -Compress -Depth 5
}
exit 0
