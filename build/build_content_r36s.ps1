<#
  build_content_r36s.ps1 — Builds a "lite" content set for the R36S:
  reuses Game\BuiltContent (shaders/audio/music/data), drops videos, and
  rebuilds all textures at a reduced resolution (default 40%) for a big win
  in GPU texture-cache/bandwidth and memory on the Mali-G31 / 1GB device.

  Font textures (Fonts\*.dds) are NOT resized (the .fnt files use pixel coords).

  Output: Game\BuiltContent-R36S   (used by build_r36s_port.ps1 via -Built)

  Prereq: pwsh build\build_content.ps1   (Game\BuiltContent must exist)
#>
[CmdletBinding()]
param([double]$TextureScale = 0.40)
$ErrorActionPreference = "Continue"

$Repo  = Split-Path -Parent $PSScriptRoot
$Src   = Join-Path $Repo "Game\ContentPC"
$Built = Join-Path $Repo "Game\BuiltContent"
$Out   = Join-Path $Repo "Game\BuiltContent-R36S"
$Tex   = Join-Path $Repo "build\_r36s_tex"

function Find-Tool($n,$c){ $x=Get-Command $n -ErrorAction SilentlyContinue; if($x){return $x.Source}; foreach($p in $c){$g=Get-ChildItem -Path $p -ErrorAction SilentlyContinue|Select-Object -First 1; if($g){return $g.FullName}}; throw "no $n" }
$Ffmpeg = Find-Tool "ffmpeg.exe" @((Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe"))
$Mgcb   = Find-Tool "mgcb.exe"   @((Join-Path $env:USERPROFILE ".dotnet\tools\mgcb.exe"))

if (-not (Test-Path (Join-Path $Built "White.xnb"))) { throw "Run build_content.ps1 first." }

Write-Host "== seed BuiltContent-R36S from BuiltContent (minus videos) ==" -ForegroundColor Cyan
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
Copy-Item $Built $Out -Recurse -Force
$mv = Join-Path $Out "Movies"; if (Test-Path $mv) { Remove-Item $mv -Recurse -Force }

Write-Host "== resize textures to $([int]($TextureScale*100))% (ffmpeg) ==" -ForegroundColor Cyan
if (Test-Path $Tex) { Remove-Item $Tex -Recurse -Force }
$dds = Get-ChildItem -Path $Src -Recurse -Filter *.dds
$n = 0; $skipFonts = 0
foreach ($f in $dds) {
    $rel = $f.FullName.Substring($Src.Length+1)
    if ($rel -like "Fonts\*") { $skipFonts++; continue }   # keep font atlases full-res
    $dst = Join-Path $Tex ([System.IO.Path]::ChangeExtension($rel, ".png"))
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    & $Ffmpeg -y -loglevel error -i $f.FullName -vf "scale='max(1,trunc(iw*$TextureScale))':'max(1,trunc(ih*$TextureScale))'" $dst
    $n++
    if ($n % 100 -eq 0) { Write-Host "  ...$n resized" }
}
Write-Host "  resized $n textures ($skipFonts font atlases kept full-res)"

Write-Host "== rebuild resized textures -> xnb (mgcb, overwrites in BuiltContent-R36S) ==" -ForegroundColor Cyan
$resp = Join-Path $Tex "_r36s.mgcb"
$lines = @(
    "/outputDir:$Out"
    "/intermediateDir:$(Join-Path $Repo 'build\_r36s_mgcb_obj')"
    "/platform:DesktopGL"; "/profile:Reach"; "/compress:False"; ""
    "/importer:TextureImporter"; "/processor:TextureProcessor"
    "/processorParam:ColorKeyEnabled=False"
    "/processorParam:PremultiplyAlpha=False"
    "/processorParam:GenerateMipmaps=False"
    "/processorParam:TextureFormat=NoChange"
)
Push-Location $Tex
Get-ChildItem -Recurse -Filter *.png | ForEach-Object { $lines += "/build:$($_.FullName.Substring($Tex.Length+1) -replace '\\','/')" }
Pop-Location
[System.IO.File]::WriteAllLines($resp, $lines, (New-Object System.Text.UTF8Encoding($false)))
Push-Location $Tex
try { & $Mgcb "/@:$resp" | Select-String -Pattern "succeeded|failed" | ForEach-Object { Write-Host "  $_" } }
finally { Pop-Location }

$xnb = (Get-ChildItem $Out -Recurse -Filter *.xnb).Count
$sz  = [math]::Round(((Get-ChildItem $Out -Recurse | Measure-Object Length -Sum).Sum/1MB),1)
Write-Host "`nDONE. BuiltContent-R36S: $xnb xnb, $sz MB" -ForegroundColor Green
