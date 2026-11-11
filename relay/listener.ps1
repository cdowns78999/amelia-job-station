# Amelia relay listener. Runs on Chad's PC only. Polls the relay every 60 seconds, runs one search at a time
# through Claude Code under the dedicated account, and sends the txt back.
# Setup: put the relay key (same value as Netlify env RELAY_KEY) in %LOCALAPPDATA%\AmeliaRelay\relay-key.txt.
# Optional: %LOCALAPPDATA%\AmeliaRelay\claude-config-dir.txt holds the CLAUDE_CONFIG_DIR of the dedicated account.
param([switch]$Once, [switch]$DryRun, [string]$Base = "https://amelia-job-hunt.netlify.app")

$ErrorActionPreference = "Stop"
$Version = "0.1.0"
$Home2 = Join-Path $env:LOCALAPPDATA "AmeliaRelay"
$Runs = Join-Path $Home2 "runs"
New-Item -ItemType Directory -Force -Path $Runs | Out-Null
$KeyFile = Join-Path $Home2 "relay-key.txt"
if (-not (Test-Path $KeyFile)) { Write-Host "No relay key at $KeyFile. Stopping."; exit 1 }
$Key = (Get-Content $KeyFile -Raw).Trim()
$CfgFile = Join-Path $Home2 "claude-config-dir.txt"
$Template = Get-Content (Join-Path $PSScriptRoot "prompt-template.txt") -Raw

function Relay($body) {
  $body.version = $Version
  Invoke-RestMethod -Method Post -Uri "$Base/api/relay" -Headers @{ "X-Relay-Key" = $Key } `
    -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 6 -Compress) -TimeoutSec 30
}
function Say($id, $line) { Write-Host $line; try { Relay @{ op = "progress"; id = $id; lines = @($line) } | Out-Null } catch {} }

function Run-Job($job) {
  $id = $job.id; $r = $job.req
  # The server already cleaned every field; check again here so nothing odd reaches the prompt.
  if ($r.lane -notin @("indeed", "linkedin")) { throw "bad lane" }
  foreach ($v in @($r.kinds + $r.cities)) { if ($v -notmatch "^[A-Za-z0-9 ,.'\-/]{1,40}$") { throw "bad field" } }
  $dir = Join-Path $Runs $id; New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir "job-search-relay-$id.txt"
  $prompt = $Template.Replace("{LANE}", $r.lane).Replace("{KINDS}", ($r.kinds -join ", ")).Replace("{CITIES}", ($(if ($r.cities) { $r.cities -join "; " } else { "remote" }))).Replace("{MILES}", "$($r.miles)").Replace("{MODE}", $r.mode).Replace("{TOTAL}", "$($r.total)").Replace("{OUT}", $out)
  Set-Content -Path (Join-Path $dir "prompt.txt") -Value $prompt -Encoding UTF8
  Say $id "Starting the $($r.lane) search."
  if ($DryRun) {
    Set-Content -Path $out -Encoding UTF8 -Value "JOB SEARCH - dry run - 1 verified live results`n`ntitle:      Dry run receptionist`nemployer:   Test Employer`ncity:       $($r.cities[0])`nmiles:      0`npay:        Not listed`nclearance:  n/a`nwhy:        dry run`nurl:        https://example.com/job`ncategory:   $($r.kinds[0])`n"
  } else {
    if (Test-Path $CfgFile) { $env:CLAUDE_CONFIG_DIR = (Get-Content $CfgFile -Raw).Trim() }
    $log = Join-Path $dir "claude.log"
    $p = Start-Process -FilePath "claude" -ArgumentList @("-p", "--chrome", "--model", "sonnet", "--permission-mode", "acceptEdits", "--max-turns", "120", "--allowedTools", $Allowed) `
      -RedirectStandardInput (Join-Path $dir "prompt.txt") -RedirectStandardOutput $log -RedirectStandardError (Join-Path $dir "claude.err") `
      -WorkingDirectory $dir -PassThru -NoNewWindow
    $sent = 0; $limit = (Get-Date).AddMinutes(40)
    while (-not $p.HasExited) {
      Start-Sleep -Seconds 15
      $lines = @(Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -match "^STEP:" })
      if ($lines.Count -gt $sent) { try { Relay @{ op = "progress"; id = $id; lines = $lines[$sent..($lines.Count - 1)] } | Out-Null } catch {}; $sent = $lines.Count }
      if ((Get-Date) -gt $limit) { Stop-Process -Id $p.Id -Force; throw "the search ran past 40 minutes" }
    }
  }
  if (-not (Test-Path $out)) { throw "the search finished without writing a results file" }
  Relay @{ op = "done"; id = $id; txt = (Get-Content $out -Raw) } | Out-Null
  Write-Host "Sent back $out"
}

# Pre-allowed tools so the headless run never stops on a permission prompt: the sweep script, reading skill files,
# writing inside its own run folder, and the Claude in Chrome browser tools. Nothing else.
$Allowed = 'Read,Write,Edit,Glob,Grep,Bash(powershell -File*amelia-job-hunt*search-live-urls.ps1*),mcp__claude-in-chrome__*'
# Startup self-check: claude, Chrome, key. The relay sees this PC as awake from the first poll.
try { $cv = (& claude --version) 2>$null; Write-Host "claude $cv" } catch { Write-Host "claude was not found on PATH. Stopping."; exit 1 }
$hasChrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ }
if (-not $hasChrome) { Write-Host "Chrome was not found. LinkedIn and Claude in Chrome searches will fail." }
Write-Host "Amelia relay listener $Version. Watching $Base every 60 seconds. Close this window to stop."
do {
  try {
    $n = Relay @{ op = "next" }
    if ($n.installer) {
      # Backdoor PUBLISH: run the fixed release script only. The note is a commit message, never a command.
      $say = { param($l) Write-Host $l; try { Relay @{ op = "inst-update"; lines = @($l) } | Out-Null } catch {} }
      try {
        $rel = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "GitHub\amelia-job-station\installer\release.ps1"
        if (-not (Test-Path $rel)) { throw "release.ps1 not found at $rel" }
        $ver = & $rel -Note ([string]$n.installer.note) -Say $say
        Relay @{ op = "inst-update"; status = "done"; version = "$ver"; lines = @("Done: version $ver") } | Out-Null
      } catch { Relay @{ op = "inst-update"; status = "failed"; lines = @("FAILED: $($_.Exception.Message)") } | Out-Null }
    }
    elseif ($n.job) {
      try { Run-Job $n.job } catch { Write-Host "FAILED: $($_.Exception.Message)"; try { Relay @{ op = "fail"; id = $n.job.id; error = $_.Exception.Message } | Out-Null } catch {} }
    }
  } catch { Write-Host "Relay not reachable: $($_.Exception.Message)" }
  if (-not $Once) { Start-Sleep -Seconds 60 }
} while (-not $Once)
