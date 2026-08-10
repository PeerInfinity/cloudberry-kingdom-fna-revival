#!/usr/bin/env bash
# apply_patches.sh — Applies this repo's patches + project files to a clone of
# PwneeStudios/Cloudberry-Kingdom.
#
# Usage:  scripts/apply_patches.sh ../Cloudberry-Kingdom
set -euo pipefail

GAME_REPO="${1:?usage: apply_patches.sh <path-to-Cloudberry-Kingdom>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES="$REPO_ROOT/patches"

[ -f "$GAME_REPO/Game/MainClass/CloudberryKingdom.cs" ] || {
  echo "Doesn't look like the Cloudberry-Kingdom repo: $GAME_REPO" >&2; exit 1; }

declare -A MAP=(
  [Resources.patch]="Game/Engine/GameTools/Resources.cs"
  [Tools.patch]="Game/Engine/GameTools/Tools.cs"
  [EzSong.patch]="Game/Engine/Song/EzSong.cs"
  [Video.patch]="Game/Engine/Video.cs"
  [CloudberryKingdom.patch]="Game/MainClass/CloudberryKingdom.cs"
  [XnaGameClass.patch]="Game/MainClass/XnaGameClass.cs"
  [ParticleEmitter.patch]="Game/Engine/ParticleEffects/ParticleEmitter.cs"
)

cd "$GAME_REPO"
for patch in "${!MAP[@]}"; do
  target="${MAP[$patch]}"
  # Patches are LF; normalize the target to LF so they apply cleanly.
  tmp="$(mktemp)"; tr -d '\r' < "$target" > "$tmp" && mv "$tmp" "$target"
  git -c core.autocrlf=false apply --whitespace=nowarn "$PATCHES/$patch"
  echo "  applied $patch"
done
cp "$PATCHES/Game.Core.csproj" "Game/Game.Core.csproj"
cp "$PATCHES/Game.Mono.csproj" "Game/Game.Mono.csproj"
echo "  copied Game.Core.csproj + Game.Mono.csproj"

# The build scripts expect to run from the game-repo root; deploy them into the clone.
mkdir -p build && cp -r "$REPO_ROOT/build/." build/
echo "  deployed build/ scripts into the game repo"
echo
echo "Done. Next: put FNA as a sibling of this clone, fnalibs in build/fnalibs,"
echo "then run build/build_content.ps1 and build/build_release.ps1 -SkipContent from here."
