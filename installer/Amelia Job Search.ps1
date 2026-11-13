# Amelia Job Search: installer, updater and launcher in one file (built into Amelia Job Search.exe by build-exe.ps1).
# Every run: loading screen -> install if missing -> check GitHub for a newer widget -> open the widget window.
# Touches only %LOCALAPPDATA%\AmeliaJobStation and one Desktop shortcut. No admin, no services, no hidden tasks.
param([switch]$NoWindow, [switch]$Handoff)
$LauncherVersion = "1.1.1"
$ErrorActionPreference = "Stop"
$Repo = "https://raw.githubusercontent.com/cdowns78999/amelia-job-station/main"
$Home2 = Join-Path $env:LOCALAPPDATA "AmeliaJobSearch"
$Widget = Join-Path $Home2 "widget.html"
$VerFile = Join-Path $Home2 "version.json"
$Profile2 = Join-Path $Home2 "chrome-profile"
$Log = Join-Path $Home2 "launcher.log"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# ---------- loading window, EGA colours ----------
$f = New-Object Windows.Forms.Form
$f.FormBorderStyle = "None"; $f.StartPosition = "CenterScreen"; $f.Size = New-Object Drawing.Size(520, 240)
$f.BackColor = [Drawing.Color]::FromArgb(0, 0, 170); $f.TopMost = $true; $f.Opacity = 0
$t = New-Object Windows.Forms.Label; $t.Text = "AMELIA JOB SEARCH"; $t.ForeColor = [Drawing.Color]::FromArgb(255, 255, 85)
$t.Font = New-Object Drawing.Font("Consolas", 20, [Drawing.FontStyle]::Bold); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(24, 30)
$s = New-Object Windows.Forms.Label; $s.Text = "LOADING..."; $s.ForeColor = [Drawing.Color]::FromArgb(85, 255, 255)
$s.Font = New-Object Drawing.Font("Consolas", 12); $s.AutoSize = $true; $s.Location = New-Object Drawing.Point(26, 90)
$bar = New-Object Windows.Forms.Panel; $bar.BackColor = [Drawing.Color]::Black; $bar.Location = New-Object Drawing.Point(26, 140); $bar.Size = New-Object Drawing.Size(468, 30)
$fill = New-Object Windows.Forms.Panel; $fill.BackColor = [Drawing.Color]::FromArgb(85, 255, 85); $fill.Location = New-Object Drawing.Point(3, 3); $fill.Size = New-Object Drawing.Size(0, 24)
$bar.Controls.Add($fill); $f.Controls.AddRange(@($t, $s, $bar))
function Step($text, $pct) {
  $s.Text = $text; $fill.Width = [int](462 * $pct / 100) - (([int](462 * $pct / 100)) % 22) # chunky blocks
  [Windows.Forms.Application]::DoEvents(); Add-Content -Path $Log -Value "$(Get-Date -Format s) $text" -ErrorAction SilentlyContinue
}
if (-not $NoWindow) { $f.Show(); for ($i = 0; $i -le 20; $i++) { $f.Opacity = $i / 20; [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 } }

try {
  New-Item -ItemType Directory -Force -Path $Home2 | Out-Null
  Step "CHECKING THE INSTALL" 15
  $local = if (Test-Path $VerFile) { (Get-Content $VerFile -Raw | ConvertFrom-Json).widget } else { "0.0.0" }

  Step "CHECKING FOR AN UPDATE" 40
  $remote = $null; $vj = $null
  try { $vj = Invoke-RestMethod -Uri "$Repo/version.json" -TimeoutSec 5; $remote = $vj.widget } catch { Step "OFFLINE, USING THE INSTALLED VERSION" 45 }

  # Launcher self-update (2026-11-12): when GitHub lists a newer launcher, fetch the newest launcher script,
  # check it, and hand over to it. It runs this same flow, so the widget update still happens before opening.
  if (-not $Handoff -and $vj -and $vj.launcher -and ([version]$vj.launcher -gt [version]$LauncherVersion)) {
    try {
      Step "UPDATING THE LAUNCHER TO $($vj.launcher)" 50
      $next = Join-Path $Home2 "launcher-core.ps1"
      Invoke-WebRequest -Uri "$Repo/installer/Amelia%20Job%20Search.ps1" -OutFile "$next.download" -TimeoutSec 20 -UseBasicParsing
      $code = Get-Content "$next.download" -Raw; $perr = $null
      [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$perr)
      if ($perr.Count -or $code -notmatch '\$LauncherVersion = "' -or $code.Length -lt 3000) { throw "the new launcher did not look right" }
      Move-Item "$next.download" $next -Force
      $f.Close()
      Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$next`"", "-Handoff")
      exit
    } catch { Add-Content -Path $Log -Value "$(Get-Date -Format s) launcher update skipped: $($_.Exception.Message)" -ErrorAction SilentlyContinue; Remove-Item "$Home2\launcher-core.ps1.download" -ErrorAction SilentlyContinue }
  }

  if ($remote -and ([version]$remote -gt [version]$local -or -not (Test-Path $Widget))) {
    Step "INSTALLING VERSION $remote" 65
    $tmp = "$Widget.download"
    Invoke-WebRequest -Uri "$Repo/widget/widget.html" -OutFile $tmp -TimeoutSec 20 -UseBasicParsing
    $body = Get-Content $tmp -Raw
    # sanity check before swapping: right file, sane size
    if ($body -notmatch "AMELIA" -or $body.Length -lt 5000 -or $body.Length -gt 2000000) { Remove-Item $tmp; throw "the downloaded widget did not look right, kept the old one" }
    if (Test-Path $Widget) { Copy-Item $Widget "$Widget.previous" -Force }
    Move-Item $tmp $Widget -Force
    @{ widget = $remote } | ConvertTo-Json | Set-Content $VerFile
    # the city and zip list the Job search intake uses (best effort; the widget also has an online fallback)
    try { Invoke-WebRequest -Uri "$Repo/widget/us-places.js" -OutFile (Join-Path $Home2 "us-places.js") -TimeoutSec 30 -UseBasicParsing } catch {}
  } elseif (-not (Test-Path $Widget)) {
    # GitHub not reachable (offline, or repo not public yet): install the copy bundled in the zip.
    $here = Split-Path ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
    if ($PSScriptRoot) { $here = $PSScriptRoot }
    $bund = Join-Path $here "widget.html"
    if (-not (Test-Path $bund)) { throw "no internet and no bundled widget.html next to the installer" }
    Step "INSTALLING THE BUNDLED VERSION" 65
    Copy-Item $bund $Widget -Force
    $bp = Join-Path $here "us-places.js"; if (Test-Path $bp) { Copy-Item $bp (Join-Path $Home2 "us-places.js") -Force }
    $bv = Join-Path $here "version.json"
    if (Test-Path $bv) { Copy-Item $bv $VerFile -Force } else { @{ widget = "0.0.0" } | ConvertTo-Json | Set-Content $VerFile }
  }

  Step "MAKING THE SHORTCUT" 85
  # J icon for the shortcut (the EXE carries it too); fetched once, then reused
  $ico = Join-Path $Home2 "amelia.ico"
  if (-not (Test-Path $ico)) { try { Invoke-WebRequest -Uri "$Repo/installer/art/amelia.ico" -OutFile $ico -TimeoutSec 15 -UseBasicParsing } catch {} }
  $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "Amelia Job Search.lnk"
  $self = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  if ($self -match "\\Amelia Job Search\.exe$") {
    $exeHome = Join-Path $Home2 "Amelia Job Search.exe"
    if ($self -ne $exeHome) { Copy-Item $self $exeHome -Force }
    if (-not (Test-Path $lnk)) { $w = New-Object -ComObject WScript.Shell; $sc = $w.CreateShortcut($lnk); $sc.TargetPath = $exeHome; $sc.WorkingDirectory = $Home2; if (Test-Path $ico) { $sc.IconLocation = "$ico,0" }; $sc.Save() }
  } elseif (-not (Test-Path $lnk)) {
    # Started from the .ps1 or the backup .bat: keep a copy of this script in the install folder and point the
    # Desktop shortcut at it (or at the installed exe, if an earlier exe run left one), so there is always one shortcut.
    $exeHome = Join-Path $Home2 "Amelia Job Search.exe"
    $w = New-Object -ComObject WScript.Shell; $sc = $w.CreateShortcut($lnk); $sc.WorkingDirectory = $Home2
    if (Test-Path $exeHome) { $sc.TargetPath = $exeHome }
    elseif ($PSCommandPath) {
      $psHome2 = Join-Path $Home2 "Amelia Job Search.ps1"
      if ($PSCommandPath -ne $psHome2) { Copy-Item $PSCommandPath $psHome2 -Force }
      $sc.TargetPath = "powershell.exe"
      $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$psHome2`""
    }
    if ($sc.TargetPath) { if (Test-Path $ico) { $sc.IconLocation = "$ico,0" }; $sc.Save() }
  }

  $chromePath = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  Step "RUNNING THE CONNECTION CHECKS" 92
  # Real checks, no API keys. Results go to checks.js beside the widget so the first-open screen can show them.
  function Chk($name, $ok, $note) { [pscustomobject]@{ name = $name; ok = [bool]$ok; note = $note } }
  $checks = @()
  $checks += Chk "Widget installed" (Test-Path $Widget) $Widget
  $gh = $null; try { $gh = Invoke-RestMethod -Uri "$Repo/version.json" -TimeoutSec 5 } catch {}
  $checks += Chk "GitHub update channel" ($null -ne $gh) $(if ($gh) { "latest widget $($gh.widget)" } else { "could not reach the repo" })
  $app = $false; try { $r = Invoke-WebRequest -Uri "https://amelia-job-hunt.netlify.app/api/relay" -Method Options -TimeoutSec 8 -UseBasicParsing; $app = ($r.StatusCode -eq 204) } catch {}
  $checks += Chk "Amelia Job Search app (Netlify)" $app $(if ($app) { "relay answering" } else { "relay not answering yet" })
  $gsi = $false; try { $g = Invoke-WebRequest -Uri "https://accounts.google.com/gsi/client" -TimeoutSec 8 -UseBasicParsing; $gsi = ($g.StatusCode -eq 200) } catch {}
  $checks += Chk "Google sign-in reachable" $gsi "used to pair on the app"
  $checks += Chk "Chrome installed" ([bool]$chromePath) $(if ($chromePath) { $chromePath } else { "install Google Chrome" })
  $docs = [Environment]::GetFolderPath("MyDocuments")
  $resume = Join-Path $docs "Resume"
  # Save them a step: make Documents\Resume if it is missing. Never touches files already inside it.
  if (-not (Test-Path $resume)) { try { New-Item -ItemType Directory -Path $resume -Force | Out-Null } catch {} }
  $checks += Chk "Resume folder" (Test-Path $resume) $resume
  # One-click links for the widget (2026-11-12), current user only, no admin:
  #   ameliajobs://resume  opens Documents\Resume in File Explorer
  #   ameliajobs://copy    copies the newest resume PDF from Downloads (last 20 minutes) into Documents\Resume
  # The helper only knows these two fixed jobs. Anything else in the link just opens the folder.
  try {
    $helper = Join-Path $Home2 "resume-helper.ps1"
    Set-Content -Path $helper -Encoding UTF8 -Value @'
param([string]$Link = "")
$resume = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Resume"
if (-not (Test-Path $resume)) { New-Item -ItemType Directory -Path $resume -Force | Out-Null }
Add-Type -AssemblyName System.Windows.Forms
function Note($m) { [System.Windows.Forms.MessageBox]::Show($m, "Amelia Job Search") | Out-Null }
if ($Link -match '^ameliajobs://copy/?$') {
  $dl = Join-Path $env:USERPROFILE "Downloads"
  try { $x = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -ErrorAction Stop)."{374DE290-123F-4565-9164-39C4925E467B}"; if ($x -and (Test-Path $x)) { $dl = $x } } catch {}
  $since = (Get-Date).AddMinutes(-20)
  $pdfs = @(Get-ChildItem -Path $dl -Filter *.pdf -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since -and $_.Length -gt 1000 })
  if (-not $pdfs.Count) { Note "No PDF was downloaded in the last 20 minutes. Download your resume from Gemini first, then press Run copy again."; exit }
  # resume in the name wins, then the newest one
  $pick = $pdfs | Sort-Object @{ Expression = { $_.Name -match 'resume|cv' }; Descending = $true }, @{ Expression = { $_.LastWriteTime }; Descending = $true } | Select-Object -First 1
  $n = 1; while (Test-Path (Join-Path $resume "Resume copy $n.pdf")) { $n++ }
  $dest = Join-Path $resume "Resume copy $n.pdf"
  Copy-Item -LiteralPath $pick.FullName -Destination $dest
  Start-Process explorer.exe -ArgumentList "/select,`"$dest`""
  exit
}
Start-Process explorer.exe -ArgumentList "`"$resume`""
'@
    $cls = "HKCU:\Software\Classes\ameliajobs"
    New-Item -Path "$cls\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path $cls -Name "(default)" -Value "URL:Amelia Job Search"
    Set-ItemProperty -Path $cls -Name "URL Protocol" -Value ""
    Set-ItemProperty -Path "$cls\shell\open\command" -Name "(default)" -Value ("`"$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$helper`" `"%1`"")
  } catch {}
  $checks += Chk "Open Resume folder link" (Test-Path "HKCU:\Software\Classes\ameliajobs\shell\open\command") "the widget's Open my Resume folder link"
  $json = @{ at = (Get-Date -Format s); version = $(if (Test-Path $VerFile) { (Get-Content $VerFile -Raw | ConvertFrom-Json).widget } else { "0.0.0" }); checks = $checks } | ConvertTo-Json -Depth 4 -Compress
  Set-Content -Path (Join-Path $Home2 "checks.js") -Value "window.AJS_CHECKS = $json;" -Encoding UTF8

  Step "OPENING THE STATION" 100
  $chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  $ver = if (Test-Path $VerFile) { (Get-Content $VerFile -Raw | ConvertFrom-Json).widget } else { "0.0.0" }
  $url = "file:///" + ($Widget -replace "\\", "/") + "?v=" + $ver + "&l=" + $LauncherVersion
  if ($chrome) { Start-Process $chrome -ArgumentList @("--app=$url", "--user-data-dir=$Profile2", "--window-size=820,900", "--allow-file-access-from-files") }
  else { Start-Process $url }
  Start-Sleep -Milliseconds 600
} catch {
  Step "PROBLEM: $($_.Exception.Message)" 100
  [Windows.Forms.MessageBox]::Show("Amelia Job Search could not finish: $($_.Exception.Message)`nThe log is at $Log", "Amelia Job Search") | Out-Null
} finally { if (-not $NoWindow) { $f.Close() } }
