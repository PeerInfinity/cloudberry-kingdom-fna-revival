<#
  build_release.ps1 — Produces a self-contained Windows x64 release of
  Cloudberry Kingdom in dist\CloudberryKingdom (no .NET install required to run).

  Steps:
    1. (optional) rebuild content via build_content.ps1
    2. dotnet publish  (win-x64, self-contained, no trim)
    3. drop in the FNA native libraries (SDL3/FNA3D/FAudio/Theorafile + D3D12)
    4. copy BuiltContent -> Content
    5. tidy up (remove .pdb)

  Usage:
    pwsh build/build_release.ps1              # full (rebuilds content first)
    pwsh build/build_release.ps1 -SkipContent # reuse existing Game\BuiltContent
#>
[CmdletBinding()]
param([switch]$SkipContent)
$ErrorActionPreference = "Continue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Proj     = Join-Path $RepoRoot "Game\Game.Core.csproj"
$Built    = Join-Path $RepoRoot "Game\BuiltContent"
$Native   = Join-Path $RepoRoot "build\fnalibs"
$Dist     = Join-Path $RepoRoot "dist\CloudberryKingdom"

function Find-Tool([string]$name, [string[]]$candidates) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $candidates) {
        $g = Get-ChildItem -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { return $g.FullName }
    }
    throw "Could not locate '$name'."
}
$Dotnet = Find-Tool "dotnet.exe" @("C:\Program Files\dotnet\dotnet.exe")

# 1) Content ----------------------------------------------------------------
if (-not $SkipContent) {
    Write-Host "== Building content ==" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "build_content.ps1")
}
if (-not (Test-Path (Join-Path $Built "White.xnb"))) {
    throw "BuiltContent missing/incomplete. Run without -SkipContent first."
}

# 2) Publish ----------------------------------------------------------------
Write-Host "`n== dotnet publish (win-x64, self-contained) ==" -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
& $Dotnet publish $Proj -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=false -p:PublishTrimmed=false -p:DebugType=none `
    -o $Dist | Select-Object -Last 3
if (-not (Test-Path (Join-Path $Dist "CloudberryKingdom.exe"))) {
    throw "Publish failed: CloudberryKingdom.exe not produced."
}

# 3) Native libraries -------------------------------------------------------
Write-Host "`n== FNA native libraries (x64) ==" -ForegroundColor Cyan
Copy-Item (Join-Path $Native "x64\*.dll") $Dist -Force
# D3D12Core.dll is optional (only used by FNA3D's D3D12 backend; we default to Vulkan).
$d3d12 = Join-Path $Native "D3D12"
if (Test-Path $d3d12) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Dist "D3D12") | Out-Null
    Copy-Item (Join-Path $d3d12 "*.dll") (Join-Path $Dist "D3D12") -Force
}

# 4) Content ----------------------------------------------------------------
Write-Host "== Content ==" -ForegroundColor Cyan
Copy-Item $Built (Join-Path $Dist "Content") -Recurse -Force

# 5) Tidy -------------------------------------------------------------------
Get-ChildItem $Dist -Filter *.pdb | Remove-Item -Force -ErrorAction SilentlyContinue

$sizeMB = [math]::Round(((Get-ChildItem $Dist -Recurse | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "`nDONE. Release at: $Dist  ($sizeMB MB)" -ForegroundColor Green
Write-Host "Run it: `"$Dist\CloudberryKingdom.exe`""
