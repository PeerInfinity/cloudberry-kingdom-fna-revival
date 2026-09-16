<#
  apply_patches.ps1 — Applies this repo's patches + project files to a clone of
  PwneeStudios/Cloudberry-Kingdom.

  Usage:  pwsh scripts/apply_patches.ps1 -GameRepo ..\Cloudberry-Kingdom [-UpstreamOnly | -BrowserOnly]

    (default)      the upstream revival patches, then this fork's patches/browser/ set
    -UpstreamOnly  only the upstream revival patches (the full-content PC / R36S build, as upstream ships it)
    -BrowserOnly   only patches/browser/ (onto a clone that already has the upstream set applied)
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GameRepo, [switch]$UpstreamOnly, [switch]$BrowserOnly)
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Patches  = Join-Path $RepoRoot "patches"
$sentinel = Join-Path $GameRepo "Game\MainClass\CloudberryKingdom.cs"
if (-not (Test-Path $sentinel)) { throw "Doesn't look like the Cloudberry-Kingdom repo: $GameRepo" }

# patch file -> target (relative to the game repo)
$map = [ordered]@{
    "Resources.patch"         = "Game\Engine\GameTools\Resources.cs"
    "Tools.patch"             = "Game\Engine\GameTools\Tools.cs"
    "EzSong.patch"            = "Game\Engine\Song\EzSong.cs"
    "Video.patch"             = "Game\Engine\Video.cs"
    "CloudberryKingdom.patch" = "Game\MainClass\CloudberryKingdom.cs"
    "XnaGameClass.patch"      = "Game\MainClass\XnaGameClass.cs"
    "ParticleEmitter.patch"   = "Game\Engine\ParticleEffects\ParticleEmitter.cs"
}

Push-Location $GameRepo
try {
  if (-not $BrowserOnly) {
    foreach ($kv in $map.GetEnumerator()) {
        $target = $kv.Value
        # The patches are LF; a Windows clone may be CRLF. Normalize the target to LF
        # (keeping any BOM) so the diffs apply cleanly. Line endings don't affect the build.
        $bytes = [System.IO.File]::ReadAllText($target)
        [System.IO.File]::WriteAllText($target, ($bytes -replace "`r`n","`n"))
        git -c core.autocrlf=false apply --whitespace=nowarn (Join-Path $Patches $kv.Key)
        Write-Host "  applied $($kv.Key)" -ForegroundColor Green
    }
    Copy-Item (Join-Path $Patches "Game.Core.csproj") "Game\Game.Core.csproj" -Force
    Copy-Item (Join-Path $Patches "Game.Mono.csproj") "Game\Game.Mono.csproj" -Force
    Write-Host "  copied Game.Core.csproj + Game.Mono.csproj" -ForegroundColor Green

    # The build scripts expect to run from the game-repo root (they use Game\ContentPC,
    # ..\..\FNA, build\fnalibs, ...). Deploy them into the clone.
    New-Item -ItemType Directory -Force -Path "build" | Out-Null
    Copy-Item (Join-Path $RepoRoot "build\*") "build\" -Recurse -Force
    Write-Host "  deployed build/ scripts into the game repo" -ForegroundColor Green
  }

  # This fork's set: patches\browser\series lists "patch<TAB>file<TAB>target" and "file<TAB>source<TAB>target"
  # (written by scripts/export_patches.sh). Diffs first, then the new files, in the series' order.
  if (-not $UpstreamOnly) {
    $series = Get-Content (Join-Path $Patches "browser\series") | ForEach-Object { ,($_ -split "`t") }
    foreach ($row in $series) {
        if ($row[0] -ne "patch") { continue }
        $target = Join-Path (Get-Location) $row[2]
        # Byte-level CRLF -> LF, so a UTF-8 BOM stays where the diff expects it.
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($target))
        [System.IO.File]::WriteAllBytes($target, [System.Text.Encoding]::GetEncoding(28591).GetBytes(($text -replace "`r`n","`n")))
        git -c core.autocrlf=false apply --whitespace=nowarn (Join-Path $Patches ("browser\" + $row[1]))
        if ($LASTEXITCODE -ne 0) { throw "git apply failed: browser\$($row[1])" }
        Write-Host "  applied browser\$($row[1])" -ForegroundColor Green
    }
    foreach ($row in $series) {
        if ($row[0] -ne "file") { continue }
        $target = Join-Path (Get-Location) $row[2]
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item (Join-Path $Patches ("browser\" + $row[1])) $target -Force
        Write-Host "  copied browser\$($row[1]) -> $($row[2])" -ForegroundColor Green
    }
  }
}
finally { Pop-Location }
Write-Host "`nDone. Next:" -ForegroundColor Cyan
Write-Host "  1) put FNA at  <parent-of-this-clone>\FNA  (sibling of the game repo)"
Write-Host "  2) put fnalibs at  $GameRepo\build\fnalibs   (see README)"
Write-Host "  3) cd `"$GameRepo`"  then run  build\build_content.ps1  and  build\build_release.ps1 -SkipContent"
Write-Host "  Browser page: build/browser/build.sh (Linux or WSL; see build/browser/README.md)"
