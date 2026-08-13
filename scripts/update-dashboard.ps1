# Runs the CBS auto-update check for housing_construction_dashboard.html.
# Invoked daily by a Windows Scheduled Task ("HousingDashboardAutoUpdate").
# Safe to run manually too: it only commits/pushes if it finds and validates
# a genuinely newer CBS release; otherwise it's a no-op.
#
# NOTE ON ERROR HANDLING (learned the hard way, 2026-08-13):
# Do NOT set $ErrorActionPreference='Stop' globally here, and do NOT capture
# the claude call with `2>&1` into a variable. In Windows PowerShell 5.1 that
# combination turns any stderr line from a native exe into a TERMINATING
# NativeCommandError, which killed this script before it logged anything --
# producing silent 94-byte logs and exit code 1 with no diagnostics.
# Native streams are redirected to files instead, which does not wrap them.

$ErrorActionPreference = 'Continue'

$repoDir = "C:\Users\Ayelet Lironne\housing-dashboard"
$logDir = Join-Path $repoDir "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logFile = Join-Path $logDir "update-$timestamp.log"
$outFile = Join-Path $logDir "claude-stdout-$timestamp.txt"
$errFile = Join-Path $logDir "claude-stderr-$timestamp.txt"

function Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

Log "=== Starting update check ==="
Log "PowerShell: $($PSVersionTable.PSVersion) | User: $env:USERNAME"
Log "ANTHROPIC_API_KEY present: $([bool]$env:ANTHROPIC_API_KEY)"

Set-Location $repoDir

# --- claude on PATH? ---
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($null -eq $claudeCmd) {
    Log "FATAL: 'claude' not found on PATH in this shell. Aborting."
    exit 1
}
Log "claude resolved to: $($claudeCmd.Source)"

# --- sync first, so we never work on stale files ---
$pullOut = & git pull --quiet 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Log "FATAL: git pull failed (exit $LASTEXITCODE): $pullOut"
    Log "Aborting so we don't risk a conflicting push."
    exit 1
}
Log "git pull ok."

# --- run the actual check ---
$promptFile = Join-Path $repoDir "scripts\update-prompt.txt"
if (-not (Test-Path $promptFile)) {
    Log "FATAL: prompt file missing at $promptFile"
    exit 1
}
$prompt = Get-Content $promptFile -Raw -Encoding utf8
Log "Prompt loaded ($($prompt.Length) chars). Invoking claude -p ..."

$prompt | & claude -p `
    --permission-mode bypassPermissions `
    --tools "Bash,Read,Write,Edit,Glob,Grep,WebSearch" `
    --model claude-sonnet-5 `
    --output-format text `
    --no-session-persistence 1> $outFile 2> $errFile

$claudeExit = $LASTEXITCODE
Log "claude exited with code: $claudeExit"

if (Test-Path $outFile) {
    $stdout = Get-Content $outFile -Raw -Encoding utf8
    if ($stdout -and $stdout.Trim().Length -gt 0) {
        Log "--- claude stdout ---"
        $stdout.TrimEnd() -split "`n" | ForEach-Object { Log "  $_" }
    } else {
        Log "(claude produced no stdout)"
    }
}

if (Test-Path $errFile) {
    $stderr = Get-Content $errFile -Raw -Encoding utf8
    if ($stderr -and $stderr.Trim().Length -gt 0) {
        Log "--- claude stderr ---"
        $stderr.TrimEnd() -split "`n" | ForEach-Object { Log "  $_" }
    }
}

Log "=== Run finished (claude exit $claudeExit) ==="
exit $claudeExit
