# WidgetUpdate.ps1: the shared launch-time update check. One file, reused by every widget launcher.
# A launcher dot-sources this file, then calls Invoke-WidgetUpdate once per launch, right after its loading screen is up.
#   . "$here\WidgetUpdate.ps1"
#   $r = Invoke-WidgetUpdate -Name "Amelia Job Search" -RepoRaw "https://raw.githubusercontent.com/<owner>/<repo>/main" `
#          -InstallDir $Home2 -WidgetFile "widget.html" -RepoWidgetPath "widget/widget.html" -Say { param($text,$pct) ... }
# Returns @{ local; remote; updated; offline }. Never throws for being offline; a bad download keeps the old widget.
# Needs a version.json at the repo root shaped like {"widget":"1.2.3"}.
function Invoke-WidgetUpdate {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$RepoRaw,
    [Parameter(Mandatory)][string]$InstallDir,
    [string]$WidgetFile = "widget.html",
    [string]$RepoWidgetPath = "widget/widget.html",
    [string]$MustContain = "",          # text the downloaded widget must contain (sanity check), default: the widget Name in caps
    [int]$TimeoutSec = 5,
    [scriptblock]$Say = { param($text, $pct) }
  )
  if (-not $MustContain) { $MustContain = $Name.Split(" ")[0].ToUpper() }
  $widget  = Join-Path $InstallDir $WidgetFile
  $verFile = Join-Path $InstallDir "version.json"
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  $result = [ordered]@{ local = "0.0.0"; remote = $null; updated = $false; offline = $false }
  if (Test-Path $verFile) { try { $result.local = (Get-Content $verFile -Raw | ConvertFrom-Json).widget } catch {} }

  & $Say "CHECKING FOR AN UPDATE" 40
  try { $result.remote = (Invoke-RestMethod -Uri "$RepoRaw/version.json" -TimeoutSec $TimeoutSec).widget }
  catch { $result.offline = $true; & $Say "OFFLINE, USING THE INSTALLED VERSION" 45 }

  if ($result.remote -and ([version]$result.remote -gt [version]$result.local -or -not (Test-Path $widget))) {
    & $Say "INSTALLING VERSION $($result.remote)" 65
    $tmp = "$widget.download"
    try {
      Invoke-WebRequest -Uri "$RepoRaw/$RepoWidgetPath" -OutFile $tmp -TimeoutSec 20 -UseBasicParsing
      $body = Get-Content $tmp -Raw
      # sanity check before swapping: right file, sane size
      if ($body -notmatch [regex]::Escape($MustContain) -or $body.Length -lt 5000 -or $body.Length -gt 2000000) { throw "the downloaded widget did not look right" }
      if (Test-Path $widget) { Copy-Item $widget "$widget.previous" -Force }
      Move-Item $tmp $widget -Force
      @{ widget = $result.remote } | ConvertTo-Json | Set-Content $verFile
      $result.updated = $true
    } catch {
      if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
      & $Say "UPDATE FAILED, KEEPING THE INSTALLED VERSION" 50
      if (-not (Test-Path $widget)) { throw }   # nothing installed yet: let the launcher fall back to its bundled copy
    }
  }
  return [pscustomobject]$result
}
