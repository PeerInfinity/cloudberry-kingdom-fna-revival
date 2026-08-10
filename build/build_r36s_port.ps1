<#
  build_r36s_port.ps1 — Assembles a PortMaster port of Cloudberry Kingdom for the
  R36S / ArkOS, modeled on the proven "Dust: An Elysian Tail" FNA-on-Mono port.

  Reuses the Dust runtime (native libs, classic SDL2 FNA.dll, MMLoader, hacksdl)
  from build\r36s-base, our net472 CloudberryKingdom.exe, and our built Content.

  Output: dist\CloudberryKingdom-Port\  (copy its contents into the R36S /roms/ports)

  Prereqs:
    - build\r36s-base  populated from a Dust install (libs, dlls, tools, MMLoader.exe,
      gamecontrollerdb.txt)
    - Game\BuiltContent  (pwsh build\build_content.ps1)
#>
$ErrorActionPreference = "Continue"
$Repo   = Split-Path -Parent $PSScriptRoot
$Proj   = Join-Path $Repo "Game\Game.Mono.csproj"
$Base   = Join-Path $Repo "build\r36s-base"
# Prefer the resized "lite" R36S content when present; fall back to full content.
$Built  = Join-Path $Repo "Game\BuiltContent-R36S"
if (-not (Test-Path $Built)) { $Built = Join-Path $Repo "Game\BuiltContent" }
$OutRoot= Join-Path $Repo "dist\CloudberryKingdom-Port"
$Port   = Join-Path $OutRoot "cloudberry"
$Game   = Join-Path $Port "gamedata"

function Find-Tool($n,$c){ $x=Get-Command $n -ErrorAction SilentlyContinue; if($x){return $x.Source}; foreach($p in $c){$g=Get-ChildItem -Path $p -ErrorAction SilentlyContinue|Select-Object -First 1; if($g){return $g.FullName}}; throw "no $n" }
$Dotnet = Find-Tool "dotnet.exe" @("C:\Program Files\dotnet\dotnet.exe")

if (-not (Test-Path (Join-Path $Base "MMLoader.exe"))) { throw "build\r36s-base missing (populate from a Dust install)." }
if (-not (Test-Path (Join-Path $Built "White.xnb")))   { throw "Game\BuiltContent missing (run build_content.ps1)." }

Write-Host "== build CloudberryKingdom.exe (net472, vs classic FNA) ==" -ForegroundColor Cyan
& $Dotnet build $Proj -c Release | Select-Object -Last 2
$exe = Join-Path $Repo "Game\bin\Release\net472\CloudberryKingdom.exe"
if (-not (Test-Path $exe)) { throw "net472 build failed." }

Write-Host "== assemble port ==" -ForegroundColor Cyan
if (Test-Path $OutRoot) { Remove-Item $OutRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Game | Out-Null

# Runtime from Dust base
Copy-Item (Join-Path $Base "libs")  $Port -Recurse -Force
Copy-Item (Join-Path $Base "dlls")  $Port -Recurse -Force
Copy-Item (Join-Path $Base "tools") $Port -Recurse -Force
Copy-Item (Join-Path $Base "MMLoader.exe") $Port -Force

# Our game + content
Copy-Item $exe $Game -Force
Copy-Item "$exe.config" $Game -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Base "gamecontrollerdb.txt") $Game -Force -ErrorAction SilentlyContinue
Copy-Item $Built (Join-Path $Game "Content") -Recurse -Force
# Handheld: drop videos (Theora decode is slow on the A35 and bloats the SD).
# StartVideo() skips gracefully when a .ogv is missing.
$movies = Join-Path $Game "Content\Movies"
if (Test-Path $movies) { Remove-Item $movies -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $Port "savedata") | Out-Null

# Launcher (.sh) + port.json  (force LF line endings, no BOM)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sh = Get-Content (Join-Path $PSScriptRoot "r36s-launcher.sh") -Raw
[System.IO.File]::WriteAllText((Join-Path $OutRoot "Cloudberry Kingdom.sh"), ($sh -replace "`r`n","`n"), $utf8)
Copy-Item (Join-Path $PSScriptRoot "r36s-port.json") (Join-Path $Port "port.json") -Force

$sizeMB = [math]::Round(((Get-ChildItem $OutRoot -Recurse | Measure-Object Length -Sum).Sum/1MB),1)
Write-Host "`nDONE. Port at: $OutRoot  ($sizeMB MB)" -ForegroundColor Green
Write-Host "Copy 'Cloudberry Kingdom.sh' AND 'cloudberry\' into the R36S  <SD>/ports/  (or /roms/ports/)."
