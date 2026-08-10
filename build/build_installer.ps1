<#
  build_installer.ps1 — Compiles build\installer.iss into
  dist\CloudberryKingdom-Setup-<ver>.exe using Inno Setup (ISCC.exe).

  Requires the self-contained release to exist first:
    pwsh build/build_release.ps1
  Requires Inno Setup 6:  winget install JRSoftware.InnoSetup
#>
$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Iss = Join-Path $PSScriptRoot "installer.iss"
$Dist = Join-Path $RepoRoot "dist\CloudberryKingdom"

if (-not (Test-Path (Join-Path $Dist "CloudberryKingdom.exe"))) {
    throw "dist\CloudberryKingdom not found. Run build_release.ps1 first."
}

# Prefer a standard Inno Setup 6 install; fall back to a filesystem search.
$Iscc = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) {
    $Iscc = Get-ChildItem "C:\Program Files (x86)","C:\Program Files" -Recurse -Filter ISCC.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Iscc) { throw "ISCC.exe not found. Install Inno Setup 6 (winget install JRSoftware.InnoSetup)." }
Write-Host "ISCC: $Iscc"

& $Iscc $Iss | Select-Object -Last 4
$out = Get-ChildItem (Join-Path $RepoRoot "dist\*.exe") | Sort-Object LastWriteTime | Select-Object -Last 1
if ($out) { Write-Host ("`nInstaller: {0} ({1:N1} MB)" -f $out.FullName, ($out.Length/1MB)) -ForegroundColor Green }
