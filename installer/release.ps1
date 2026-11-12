# Amelia Job Search: publish a new installer and widget version. Runs on Chad's PC only, started by the listener when
# Chad presses PUBLISH on the backdoor's INSTALLER panel. Fixed steps, no free text is ever run.
#   1 back up   2 copy sources in   3 bump version   4 rebuild EXE   5 rebuild setup zip   6 commit + push
param([string]$Note = "", [scriptblock]$Say = { param($l) Write-Host $l })
$ErrorActionPreference = "Stop"
$Repo   = Split-Path $PSScriptRoot -Parent
$GitHub = Split-Path $Repo -Parent
$WSrc   = Join-Path $GitHub "00302-Widget-Master\amelia-job-station"
$RSrc   = Join-Path $GitHub "00102-build\amelia-job-hunt\relay"

& $Say "1/6 Backing up the current repo files"
$bak = Join-Path $Repo ("_backup\" + (Get-Date -Format "yyyyMMdd-HHmm"))
New-Item -ItemType Directory -Force -Path $bak | Out-Null
Copy-Item (Join-Path $Repo "widget"), (Join-Path $Repo "version.json") $bak -Recurse -Force

& $Say "2/6 Copying the newest widget, prompt and listener"
Copy-Item (Join-Path $WSrc "widget.html"), (Join-Path $WSrc "resume-prompt.txt") (Join-Path $Repo "widget") -Force
Copy-Item (Join-Path $RSrc "listener.ps1"), (Join-Path $RSrc "prompt-template.txt") (Join-Path $Repo "relay") -Force

& $Say "3/6 Bumping the version"
$vf = Join-Path $Repo "version.json"
$v = Get-Content $vf -Raw | ConvertFrom-Json
$p = $v.widget.Split("."); $new = "{0}.{1}.{2}" -f $p[0], $p[1], ([int]$p[2] + 1)
$v.widget = $new
($v | ConvertTo-Json -Compress) | Set-Content $vf -Encoding UTF8
foreach ($f in @((Join-Path $Repo "widget\widget.html"), (Join-Path $WSrc "widget.html"))) {
  $t = Get-Content $f -Raw
  $t = $t -replace 'var WIDGET_VERSION="[0-9.]+";', ('var WIDGET_VERSION="' + $new + '";') -replace '<span id="ver">v[0-9.]+</span>', ('<span id="ver">v' + $new + '</span>')
  Set-Content $f $t -Encoding UTF8 -NoNewline
}

& $Say "4/6 Rebuilding Amelia Job Search.exe"
& (Join-Path $PSScriptRoot "build-exe.ps1") | Out-Null

& $Say "5/6 Rebuilding the setup zip"
$tmp = Join-Path $env:TEMP ("ajs-setup-" + [guid]::NewGuid().ToString("N"))
$pack = Join-Path $tmp "Amelia Job Search Setup"
New-Item -ItemType Directory -Force -Path $pack | Out-Null
Copy-Item (Join-Path $PSScriptRoot "Amelia Job Search.exe"), (Join-Path $PSScriptRoot "Amelia Job Search.ps1"), (Join-Path $PSScriptRoot "Amelia Job Search (backup).bat"), (Join-Path $PSScriptRoot "WidgetUpdate.ps1") $pack
Copy-Item (Join-Path $Repo "widget\widget.html"), $vf $pack   # bundled fallback when GitHub is unreachable
@("AMELIA JOB SEARCH $new - SETUP", "", "1. Right-click this zip, choose Extract All.", "2. Double-click Amelia Job Search.exe (if Windows warns: More info, then Run anyway).",
  "3. If the exe is blocked, double-click Amelia Job Search (backup).bat instead.", "4. Follow the connection checks, then open the app, press PAIR MY WIDGET, enter your email and the AJS- code, press SEND. Chad approves you.") | Set-Content (Join-Path $pack "README.txt")
$dist = Join-Path $Repo "dist"; New-Item -ItemType Directory -Force -Path $dist | Out-Null
Compress-Archive -Path $pack -DestinationPath (Join-Path $dist "Amelia-Job-Search-Setup.zip") -Force
Remove-Item $tmp -Recurse -Force

& $Say "6/6 Committing and pushing to GitHub"
Push-Location $Repo
git add -A widget relay installer dist version.json | Out-Null
$msg = "Release $new" + $(if ($Note) { ": $Note" } else { "" })
git commit -q -m $msg | Out-Null
git push -q 2>&1 | Out-Null
$ok = $LASTEXITCODE -eq 0
Pop-Location
if (-not $ok) { throw "push failed (is the repo published and signed in?)" }
& $Say "Published $new. Installed widgets update on their next launch."
return $new
