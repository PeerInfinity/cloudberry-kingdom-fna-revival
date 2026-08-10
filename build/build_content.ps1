<#
  build_content.ps1 — Rebuilds ALL Cloudberry Kingdom content from the raw source
  assets in Game/ContentPC into a self-contained "BuiltContent" folder that the
  FNA build loads at runtime.

  Pipeline:
    * Shaders  (.fx)  -> .fxb   via fxc   (fx_2_0, MojoShader-compatible)
    * Textures (.dds) -> .xnb   via mgcb  (PremultiplyAlpha=False, NoChange)
    * Audio    (.wav) -> .xnb   via mgcb  (SoundEffect)
    * Music    (.wma) -> .ogg   via ffmpeg (Vorbis)   -> loaded by Song.FromUri
    * Video    (.wmv) -> .ogv   via ffmpeg (Theora)   -> loaded by Video.FromUriEXT
    * Data     (.tsv/.txt/.smo/.fnt/.xml) copied as-is

  Usage:
    pwsh build/build_content.ps1                 # incremental (skips up-to-date media)
    pwsh build/build_content.ps1 -Force          # rebuild everything
    pwsh build/build_content.ps1 -CopyTo "<dir>" # also mirror result into <dir>\Content
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$CopyTo
)
# "Continue" (not "Stop") because native tools (fxc) write harmless warnings to
# stderr; we validate each step by checking output files / exit codes instead.
$ErrorActionPreference = "Continue"

# ---- Paths -----------------------------------------------------------------
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src      = Join-Path $RepoRoot "Game\ContentPC"
$Out      = Join-Path $RepoRoot "Game\BuiltContent"
$Inter    = Join-Path $RepoRoot "build\_mgcb_obj"
New-Item -ItemType Directory -Force -Path $Out, $Inter | Out-Null

# ---- Tool discovery --------------------------------------------------------
function Find-Tool([string]$name, [string[]]$candidates) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $candidates) {
        # Get-ChildItem resolves wildcards to a real file path (Test-Path would
        # return the literal glob string, so we must not use it here).
        $g = Get-ChildItem -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { return $g.FullName }
    }
    throw "Could not locate '$name'. Install it or add it to PATH."
}

$Fxc = Find-Tool "fxc.exe" @(
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\fxc.exe"
)
$Mgcb = Find-Tool "mgcb.exe" @(
    (Join-Path $env:USERPROFILE ".dotnet\tools\mgcb.exe")
)
$Ffmpeg = Find-Tool "ffmpeg.exe" @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe"),
    (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffmpeg.exe")
)
Write-Host "fxc   : $Fxc"
Write-Host "mgcb  : $Mgcb"
Write-Host "ffmpeg: $Ffmpeg`n"

# ---- 1) Shaders (.fx -> .fxb) ---------------------------------------------
Write-Host "== Shaders =="
$shOut = Join-Path $Out "Shaders"; New-Item -ItemType Directory -Force -Path $shOut | Out-Null
$shOk = 0
foreach ($fx in Get-ChildItem (Join-Path $Src "Shaders\*.fx")) {
    if ($fx.BaseName -eq "RootEffect") { continue }   # include-only, no technique
    $ofx = Join-Path $shOut ($fx.BaseName + ".fxb")
    Push-Location $fx.DirectoryName
    & $Fxc /nologo /T fx_2_0 /Fo $ofx $fx.Name 2>&1 | Out-Null
    Pop-Location
    if (Test-Path $ofx) { $shOk++ } else { Write-Warning "shader FAILED: $($fx.Name)" }
}
Write-Host "  $shOk shaders -> .fxb`n"

# ---- 2+3) Textures + Audio (mgcb) -----------------------------------------
Write-Host "== Textures + Audio (mgcb) =="
# The response file MUST live in the source dir: mgcb resolves relative /build
# paths against the response file's directory (not the process CWD).
$response = Join-Path $Src "_build_content.mgcb"
$lines = @(
    "/outputDir:$Out"
    "/intermediateDir:$Inter"
    "/platform:DesktopGL"
    "/profile:Reach"
    "/compress:False"
    ""
    "/importer:TextureImporter"
    "/processor:TextureProcessor"
    "/processorParam:ColorKeyEnabled=False"
    "/processorParam:PremultiplyAlpha=False"
    "/processorParam:GenerateMipmaps=False"
    "/processorParam:TextureFormat=NoChange"
)
Push-Location $Src
$dds = Get-ChildItem -Recurse -Filter *.dds | ForEach-Object { $_.FullName.Substring($Src.Length+1) }
foreach ($f in ($dds | Sort-Object)) { $lines += "/build:$($f -replace '\\','/')" }
$lines += @("", "/importer:WavImporter", "/processor:SoundEffectProcessor")
$wav = Get-ChildItem -Recurse -Filter *.wav | ForEach-Object { $_.FullName.Substring($Src.Length+1) }
foreach ($f in ($wav | Sort-Object)) { $lines += "/build:$($f -replace '\\','/')" }
Pop-Location
# Write WITHOUT a BOM (mgcb mis-parses the first option if a UTF-8 BOM precedes it).
[System.IO.File]::WriteAllLines($response, $lines, (New-Object System.Text.UTF8Encoding($false)))
$rebuildFlag = @(); if ($Force) { $rebuildFlag = @("/rebuild") }
# mgcb quirk: relative /build paths resolve against the response-file dir ($Src),
# AND the OUTPUT sub-path is computed from the child process CWD. PowerShell sets a
# native child's CWD from $PWD, so Push-Location (which sets $PWD) is what works here.
Push-Location $Src
try {
    & $Mgcb "/@:$response" @rebuildFlag | Select-String -Pattern "succeeded|failed" | ForEach-Object { Write-Host "  $_" }
} finally {
    Pop-Location
}
Remove-Item $response -Force -ErrorAction SilentlyContinue
Write-Host ""

# ---- 4) Music (.wma -> .ogg) ----------------------------------------------
Write-Host "== Music (ffmpeg -> ogg) =="
$mOut = Join-Path $Out "Music"; New-Item -ItemType Directory -Force -Path $mOut | Out-Null
$mOk = 0
foreach ($wma in Get-ChildItem (Join-Path $Src "Music\*.wma")) {
    $ogg = Join-Path $mOut ($wma.BaseName + ".ogg")
    if ((Test-Path $ogg) -and -not $Force) { $mOk++; continue }
    & $Ffmpeg -y -loglevel error -i $wma.FullName -c:a libvorbis -q:a 5 $ogg
    if (Test-Path $ogg) { $mOk++ } else { Write-Warning "music FAILED: $($wma.Name)" }
}
Write-Host "  $mOk music tracks ready`n"

# ---- 5) Video (.wmv -> .ogv) ----------------------------------------------
Write-Host "== Video (ffmpeg -> ogv Theora) =="
$vOut = Join-Path $Out "Movies"; New-Item -ItemType Directory -Force -Path $vOut | Out-Null
$vOk = 0
foreach ($wmv in Get-ChildItem (Join-Path $Src "Movies\*.wmv")) {
    $ogv = Join-Path $vOut ($wmv.BaseName + ".ogv")
    if ((Test-Path $ogv) -and -not $Force) { $vOk++; continue }
    & $Ffmpeg -y -loglevel error -i $wmv.FullName -c:v libtheora -q:v 6 -c:a libvorbis -q:a 4 $ogv
    if (Test-Path $ogv) { $vOk++ } else { Write-Warning "video FAILED: $($wmv.Name)" }
}
Write-Host "  $vOk videos ready`n"

# ---- 6) Raw data files -----------------------------------------------------
Write-Host "== Data files (copy) =="
$dataCount = 0
Push-Location $Src
Get-ChildItem -Recurse -Include *.tsv,*.txt,*.smo,*.fnt,*.xml | ForEach-Object {
    $rel = $_.FullName.Substring($Src.Length+1)
    $dst = Join-Path $Out $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $_.FullName $dst -Force
    $dataCount++
}
Pop-Location
Write-Host "  $dataCount data files copied`n"

# ---- Optional mirror -------------------------------------------------------
if ($CopyTo) {
    $target = Join-Path $CopyTo "Content"
    Write-Host "== Mirroring to $target =="
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Copy-Item $Out $target -Recurse -Force
    Write-Host "  done`n"
}

$xnb = (Get-ChildItem $Out -Recurse -Filter *.xnb).Count
$fxb = (Get-ChildItem (Join-Path $Out 'Shaders') -Filter *.fxb).Count
Write-Host "DONE. BuiltContent: $xnb xnb, $fxb fxb, $mOk ogg, $vOk ogv  ->  $Out"
