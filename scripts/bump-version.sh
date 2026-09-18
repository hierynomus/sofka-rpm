#!/usr/bin/env bash
# Bump packaging/ to the newest sofka release on GitHub.
#
# Rewrites, in lockstep:
#   packaging/sofka.spec   Version, %global sofka_sha256_{x86_64,aarch64}, Release->0, %changelog
#   packaging/_service     download_url urls + filenames (x86_64 + aarch64 tarballs)
#
# Checksums come straight from the release's SHA256SUMS asset, so this never
# downloads the ~11 MB tarballs themselves. OBS fetches them at build time
# and the spec's %prep verifies each against its sofka_sha256_* global.
#
# Usage:
#   scripts/bump-version.sh [VERSION]     # default: newest GitHub release
#   scripts/bump-version.sh --commit ...  # also `git add` + `git commit`
#
# Exit status: 0 and prints "bumped <old> -> <new>" on a change,
#              0 and prints "up to date (<version>)" when already current.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$REPO_ROOT/packaging/sofka.spec"
SERVICE="$REPO_ROOT/packaging/_service"
GH_REPO="nklmilojevic/sofka"
RELEASES_API="https://api.github.com/repos/$GH_REPO/releases"

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

commit=0
want=""
for arg in "$@"; do
  case "$arg" in
    --commit) commit=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *)  want="$arg" ;;
  esac
done

current=$(sed -n 's/^Version:[[:space:]]*//p' "$SPEC")
[ -n "$current" ] || { echo "cannot read Version from $SPEC" >&2; exit 1; }

if [ -n "$want" ]; then
  release=$(curl -fsSL "$RELEASES_API/tags/v$want")
else
  release=$(curl -fsSL "$RELEASES_API/latest")
fi

tag=$(jq -r '.tag_name' <<<"$release")
[ -n "$tag" ] && [ "$tag" != "null" ] || { echo "could not determine release tag" >&2; exit 1; }
new="${tag#v}"

x86_64_file="sofka-${tag}-x86_64-unknown-linux-gnu.tar.gz"
aarch64_file="sofka-${tag}-aarch64-unknown-linux-gnu.tar.gz"

sums_url=$(jq -r '.assets[] | select(.name == "SHA256SUMS") | .browser_download_url' <<<"$release")
[ -n "$sums_url" ] || { echo "release $tag has no SHA256SUMS asset" >&2; exit 1; }

sums=$(curl -fsSL "$sums_url")
sha_x86_64=$(awk -v f="$x86_64_file" '$2==f{print $1}' <<<"$sums")
sha_aarch64=$(awk -v f="$aarch64_file" '$2==f{print $1}' <<<"$sums")
[ -n "$sha_x86_64" ]  || { echo "no checksum for $x86_64_file in SHA256SUMS" >&2; exit 1; }
[ -n "$sha_aarch64" ] || { echo "no checksum for $aarch64_file in SHA256SUMS" >&2; exit 1; }

if [ "$new" = "$current" ]; then
  echo "up to date ($current)"
  exit 0
fi

# Guard against an accidental downgrade (e.g. a bad --version arg).
if [ "$(printf '%s\n%s\n' "$current" "$new" | sort -V | tail -1)" != "$new" ]; then
  echo "refusing to move $current -> $new (not newer)" >&2
  exit 1
fi

echo "bumping $current -> $new"
echo "  x86_64   $sha_x86_64"
echo "  aarch64  $sha_aarch64"

# --- rewrite the spec ------------------------------------------------------
tmp=$(mktemp)
awk -v new="$new" -v shax="$sha_x86_64" -v shaa="$sha_aarch64" '
  /^%global sofka_sha256_x86_64  / { print "%global sofka_sha256_x86_64  " shax; next }
  /^%global sofka_sha256_aarch64 / { print "%global sofka_sha256_aarch64 " shaa; next }
  /^Version:[[:space:]]/           { print "Version:        " new; next }
  /^Release:[[:space:]]/           { print "Release:        0"; next }
  { print }
' "$SPEC" > "$tmp"

entry="* $(LC_ALL=C date '+%a %b %d %Y') jeroen <jeroen@hierynomus.com> - ${new}-0
- Update to upstream ${new}"
awk -v e="$entry" '
  { print }
  /^%changelog$/ && !done { print e; print ""; done=1 }
' "$tmp" > "$SPEC"
rm -f "$tmp"

# --- rewrite _service --------------------------------------------------
base_url="https://github.com/$GH_REPO/releases/download/$tag"
sed -i \
  -e "s#<param name=\"url\">.*x86_64-unknown-linux-gnu.tar.gz</param>#<param name=\"url\">${base_url}/${x86_64_file}</param>#" \
  -e "s#<param name=\"filename\">.*x86_64-unknown-linux-gnu.tar.gz</param>#<param name=\"filename\">${x86_64_file}</param>#" \
  -e "s#<param name=\"url\">.*aarch64-unknown-linux-gnu.tar.gz</param>#<param name=\"url\">${base_url}/${aarch64_file}</param>#" \
  -e "s#<param name=\"filename\">.*aarch64-unknown-linux-gnu.tar.gz</param>#<param name=\"filename\">${aarch64_file}</param>#" \
  "$SERVICE"

echo "bumped $current -> $new"

if [ "$commit" -eq 1 ]; then
  cd "$REPO_ROOT"
  git add packaging/sofka.spec packaging/_service
  git commit -m "sofka ${new}: update to upstream release

Automated bump from GitHub Releases.
SHA256 x86_64=${sha_x86_64} aarch64=${sha_aarch64} (verified in %prep at build time)."
  echo "committed"
fi
