<#
  build_r36s.ps1 — Assembles a linux-arm64 build of Cloudberry Kingdom for the
  Anbernic R36S (Rockchip RK3326 / Mali-G31 / ArkOS, aarch64).

  Produces dist\CloudberryKingdom-R36S\  containing:
    CloudberryKingdom            (aarch64 apphost) + .NET runtime + FNA.dll
    lib*.so*                     (SDL3/FNA3D/FAudio/Theorafile, aarch64)
    Content\                     (built assets)
    run.sh                       (env setup: OpenGL/GLES + KMSDRM, then launch)

  R36S has NO usable Vulkan (Panfrost/Mali-G31) -> FNA3D is forced to its
  OpenGL backend, which runs on GLES 3.1 and translates our fx_2_0 shaders
  via MojoShader.

  Prereq: pwsh build/build_content.ps1   (Game\BuiltContent must exist)
#>
$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Proj  = Join-Path $RepoRoot "Game\Game.Core.csproj"
$Built = Join-Path $RepoRoot "Game\BuiltContent"
$Native= Join-Path $RepoRoot "build\fnalibs\libaarch64"
$Dist  = Join-Path $RepoRoot "dist\CloudberryKingdom-R36S"

function Find-Tool($n,$c){ $x=Get-Command $n -ErrorAction SilentlyContinue; if($x){return $x.Source}; foreach($p in $c){$g=Get-ChildItem -Path $p -ErrorAction SilentlyContinue|Select-Object -First 1; if($g){return $g.FullName}}; throw "no $n" }
$Dotnet = Find-Tool "dotnet.exe" @("C:\Program Files\dotnet\dotnet.exe")

if (-not (Test-Path (Join-Path $Built "White.xnb"))) { throw "Run build_content.ps1 first." }

Write-Host "== dotnet publish (linux-arm64, self-contained) ==" -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
& $Dotnet publish $Proj -c Release -r linux-arm64 --self-contained true `
    -p:PublishSingleFile=false -p:PublishTrimmed=false -p:DebugType=none `
    -o $Dist | Select-Object -Last 2
if (-not (Test-Path (Join-Path $Dist "CloudberryKingdom"))) { throw "publish failed" }

Write-Host "== native libs (aarch64) + content ==" -ForegroundColor Cyan
Copy-Item (Join-Path $Native "*") $Dist -Force
Copy-Item $Built (Join-Path $Dist "Content") -Recurse -Force
Get-ChildItem $Dist -Filter *.pdb | Remove-Item -Force -ErrorAction SilentlyContinue

# run.sh — LF line endings, no BOM
$run = @'
#!/bin/bash
# Cloudberry Kingdom launcher for R36S / ArkOS (aarch64)
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
chmod +x ./CloudberryKingdom 2>/dev/null

# Find our bundled .so libraries first
export LD_LIBRARY_PATH="$HERE:$LD_LIBRARY_PATH"

# No usable Vulkan on Mali-G31 -> force FNA3D's OpenGL backend on GLES
export FNA3D_FORCE_DRIVER=OpenGL
export FNA3D_OPENGL_FORCE_ES3=1

# Render straight to the display (no X); audio via ALSA
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa

# Keep saves next to the game
export HOME="$HERE/home"
mkdir -p "$HOME"

./CloudberryKingdom "$@" > "$HERE/log.txt" 2>&1
'@
[System.IO.File]::WriteAllText((Join-Path $Dist "run.sh"), ($run -replace "`r`n","`n"), (New-Object System.Text.UTF8Encoding($false)))

$sizeMB = [math]::Round(((Get-ChildItem $Dist -Recurse | Measure-Object Length -Sum).Sum/1MB),1)
Write-Host "`nDONE. R36S build: $Dist  ($sizeMB MB)" -ForegroundColor Green
Write-Host "Copy the folder to the R36S, then run ./run.sh (see log.txt for output)."
