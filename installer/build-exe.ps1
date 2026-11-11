# Builds Amelia Job Search.exe from the .ps1 with ps2exe (installed on Chad's PC). Plain readable source, no encoding tricks.
$src = Join-Path $PSScriptRoot "Amelia Job Search.ps1"
$out = Join-Path $PSScriptRoot "Amelia Job Search.exe"
Import-Module ps2exe
Invoke-ps2exe -inputFile $src -outputFile $out -noConsole -title "Amelia Job Search" -product "Amelia Job Search" -version "0.1.0.0"
Get-Item $out | Select-Object Name, Length
