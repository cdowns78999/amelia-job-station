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

$Boards = @("weworkremotely", "remoteco", "remoteok", "flexjobs", "workingnomads", "himalayas", "wellfound")

# One request can hold several parts (2026-11-12): on site runs once per station (indeed, linkedin),
# remote runs once over the picked boards. Each part writes its own txt; the clusters are joined into one file.
function Run-Part($id, $dir, $lane, $r, $total, $deadline) {
  $out = Join-Path $dir "part-$lane.txt"
  $cities = $(if ($lane -eq "remote") { "remote" } elseif ($r.cities) { $r.cities -join "; " } else { "remote" })
  $prompt = $Template.Replace("{LANE}", $lane).Replace("{KINDS}", ($r.kinds -join ", ")).Replace("{CITIES}", $cities).Replace("{ZIP}", "$($r.zip)").Replace("{MILES}", "$($r.miles)").Replace("{MODE}", $r.mode).Replace("{BOARDS}", ((@($r.boards) | Where-Object { $_ }) -join ", ")).Replace("{TOTAL}", "$total").Replace("{OUT}", $out)
  $pf = Join-Path $dir "prompt-$lane.txt"
  Set-Content -Path $pf -Value $prompt -Encoding UTF8
  Say $id "Starting the $lane part."
  if ($DryRun) {
    $c = $(if ($lane -eq "remote") { "Remote" } else { "$($r.cities[0])" })
    Set-Content -Path $out -Encoding UTF8 -Value "JOB SEARCH - dry run - 1 verified live results`n`ntitle:      Dry run $lane job`nemployer:   Test Employer`ncity:       $c`nmiles:      0`npay:        Not listed`nclearance:  n/a`nwhy:        dry run`nurl:        https://example.com/$lane`ncategory:   $($r.kinds[0])`nsite:       $lane`n"
    return $out
  }
  if (Test-Path $CfgFile) { $env:CLAUDE_CONFIG_DIR = (Get-Content $CfgFile -Raw).Trim() }
  $log = Join-Path $dir "claude-$lane.log"
  $p = Start-Process -FilePath "claude" -ArgumentList @("-p", "--chrome", "--model", "sonnet", "--permission-mode", "acceptEdits", "--max-turns", "120", "--allowedTools", $Allowed) `
    -RedirectStandardInput $pf -RedirectStandardOutput $log -RedirectStandardError (Join-Path $dir "claude-$lane.err") `
    -WorkingDirectory $dir -PassThru -NoNewWindow
  $sent = 0
  while (-not $p.HasExited) {
    Start-Sleep -Seconds 15
    $lines = @(Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -match "^STEP:" })
    if ($lines.Count -gt $sent) { try { Relay @{ op = "progress"; id = $id; lines = $lines[$sent..($lines.Count - 1)] } | Out-Null } catch {}; $sent = $lines.Count }
    if ((Get-Date) -gt $deadline) { Stop-Process -Id $p.Id -Force; throw "the search ran past 40 minutes" }
  }
  return $out
}

function Run-Job($job) {
  $id = $job.id; $r = $job.req
  # The server already cleaned every field; check again here so nothing odd reaches the prompt.
  $mode = $(if ($r.mode -in @("onsite", "remote", "both")) { $r.mode } else { "onsite" })
  $lanes = @(@($r.lanes) + @($r.lane) | Where-Object { $_ } | Select-Object -Unique)
  foreach ($l in $lanes) { if ($l -notin @("indeed", "linkedin")) { throw "bad lane" } }
  foreach ($b in @($r.boards | Where-Object { $_ })) { if ($b -notin $Boards) { throw "bad board" } }
  foreach ($v in @($r.kinds + $r.cities)) { if ($v -and $v -notmatch "^[A-Za-z0-9 ,.'\-/]{1,40}$") { throw "bad field" } }
  if ($r.zip -and "$($r.zip)" -notmatch "^\d{5}$") { throw "bad zip" }
  $parts = @()
  if ($mode -ne "remote") { $parts += $(if ($lanes.Count) { $lanes } else { @("indeed") }) }
  if ($mode -ne "onsite") { if (-not @($r.boards | Where-Object { $_ }).Count) { throw "no remote boards picked" }; $parts += "remote" }
  $each = [math]::Max(1, [math]::Ceiling([int]$r.total / $parts.Count))
  $dir = Join-Path $Runs $id; New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $deadline = (Get-Date).AddMinutes(40)
  $clusters = @()
  foreach ($lane in $parts) {
    $f = Run-Part $id $dir $lane $r $each $deadline
    if (Test-Path $f) {
      # keep everything after the title line: the clusters, one blank line apart
      $body = ((Get-Content $f -Raw) -split "\r?\n", 2)
      if ($body.Count -gt 1 -and $body[1].Trim()) { $clusters += $body[1].Trim() }
    } else { Say $id "The $lane part wrote no results file." }
  }
  if (-not $clusters.Count) { throw "the search finished without writing a results file" }
  $out = Join-Path $dir "job-search-relay-$id.txt"
  $count = ([regex]::Matches(($clusters -join "`n"), "(?m)^\s*title:")).Count
  Set-Content -Path $out -Encoding UTF8 -Value ("JOB SEARCH - $(Get-Date -Format yyyy-MM-dd) - $count verified live results`n`n" + ($clusters -join "`n`n") + "`n")
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
