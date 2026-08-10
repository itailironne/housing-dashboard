# Runs the CBS auto-update check for housing_construction_dashboard.html.
# Invoked daily by a Windows Scheduled Task ("HousingDashboardAutoUpdate").
# Safe to run manually too: it only commits/pushes if it finds and validates
# a genuinely newer CBS release; otherwise it's a no-op.

$ErrorActionPreference = 'Stop'
$repoDir = "C:\Users\Ayelet Lironne\housing-dashboard"
$logDir = Join-Path $repoDir "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logFile = Join-Path $logDir "update-$timestamp.log"

function Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

Set-Location $repoDir

Log "Starting update check"

try {
    git pull --quiet 2>&1 | ForEach-Object { Log $_ }
} catch {
    Log "git pull failed: $_"
    Log "Aborting run (stale local state, won't risk a conflicting push)."
    exit 1
}

$promptFile = Join-Path $repoDir "scripts\update-prompt.txt"
$prompt = Get-Content $promptFile -Raw -Encoding utf8

Log "Invoking claude -p ..."
$output = $prompt | & claude -p `
    --permission-mode bypassPermissions `
    --tools "Bash,Read,Write,Edit,Glob,Grep,WebSearch" `
    --model claude-sonnet-5 `
    --output-format text `
    --no-session-persistence 2>&1

$output | ForEach-Object { Log $_ }
Log "Run finished."
