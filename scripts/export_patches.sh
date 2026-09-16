#!/usr/bin/env bash
# export_patches.sh — Regenerates patches/browser/ from two commits of a Cloudberry-Kingdom clone.
#
# Usage:  scripts/export_patches.sh <game-repo> <base-ref> <head-ref> [--new-file <path>]...
#
#   <base-ref>   the clone with THIS repo's upstream patch set applied and committed
#                (scripts/apply_patches.sh --upstream-only, then a commit)
#   <head-ref>   the same plus our changes, committed
#   --new-file   a file that <head-ref> adds and that is entirely original to this repo;
#                it is copied whole into patches/browser/files/<path>. A file the head adds
#                that is not named here is REFUSED: a new file may hold pasted game code,
#                and game code only ever leaves as diff context.
#
# Writes (after removing the old patches/browser/):
#   patches/browser/<path, '/' -> '-'>.patch   one unified diff per modified file (LF, a/ b/ labels,
#                                              3 lines of context, no index lines), as patches/*.patch
#   patches/browser/files/<path>               the named new files
#   patches/browser/series                     "<kind>\t<source>\t<target>", sorted; the apply scripts read it
# Output depends only on the two commits and the --new-file list: re-running it changes nothing.
set -euo pipefail
export LC_ALL=C

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -ge 3 ] || usage
GAME_REPO="$1" BASE="$2" HEAD="$3"; shift 3
declare -A ALLOW=()
while [ $# -gt 0 ]; do
  case "$1" in
    --new-file) [ $# -ge 2 ] || usage; ALLOW["$2"]=1; shift 2 ;;
    *) usage ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/patches/browser"
g() { git -C "$GAME_REPO" "$@"; }

[ -f "$GAME_REPO/Game/MainClass/CloudberryKingdom.cs" ] || {
  echo "Doesn't look like the Cloudberry-Kingdom repo: $GAME_REPO" >&2; exit 1; }
base_sha=$(g rev-parse --verify "$BASE^{commit}") head_sha=$(g rev-parse --verify "$HEAD^{commit}")

# Refuse before writing anything.
refused=0
while IFS=$'\t' read -r status path; do
  case "$status" in
    M) ;;
    A) [ -n "${ALLOW[$path]:-}" ] || { echo "REFUSED: $path is new in $HEAD but not named with --new-file" >&2; refused=1; } ;;
    *) echo "REFUSED: $path has status $status (only modified and allowlisted new files are exported)" >&2; refused=1 ;;
  esac
done < <(g diff --no-renames --name-status "$base_sha" "$head_sha")
for path in "${!ALLOW[@]}"; do
  [ "$(g diff --no-renames --name-status "$base_sha" "$head_sha" -- "$path" | cut -f1)" = A ] || {
    echo "REFUSED: --new-file $path is not a file that $HEAD adds" >&2; refused=1; }
done
[ $refused -eq 0 ] || exit 1

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
rm -rf "$OUT"; mkdir -p "$OUT"
: > "$tmp/series"
while IFS=$'\t' read -r status path; do
  case "$status" in
    M)
      name="${path//\//-}.patch"
      g show "$base_sha:$path" | tr -d '\r' > "$tmp/a"
      g show "$head_sha:$path" | tr -d '\r' > "$tmp/b"
      # diff exits 1 when the files differ; that is the expected case.
      diff -u --label "a/$path" --label "b/$path" "$tmp/a" "$tmp/b" > "$OUT/$name" || [ $? -eq 1 ]
      printf 'patch\t%s\t%s\n' "$name" "$path" >> "$tmp/series"
      ;;
    A)
      mkdir -p "$OUT/files/$(dirname "$path")"
      g show "$head_sha:$path" | tr -d '\r' > "$OUT/files/$path"
      printf 'file\tfiles/%s\t%s\n' "$path" "$path" >> "$tmp/series"
      ;;
  esac
done < <(g diff --no-renames --name-status "$base_sha" "$head_sha")
sort "$tmp/series" > "$OUT/series"

echo "exported $(grep -c '^patch' "$OUT/series") patches + $(grep -c '^file' "$OUT/series") new files"
echo "  base $base_sha"
echo "  head $head_sha"
echo "  into $OUT"
