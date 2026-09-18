#!/usr/bin/env bash
# Build the RPM locally from packaging/, for testing before it hits OBS.
#
# Fetches the release tarball for the host's arch (the same file OBS would
# download for that arch), drops it in a throwaway rpmbuild tree, and builds
# the binary RPM. The spec's %prep verifies its SHA256, so a mismatch fails
# here exactly as it would on OBS.
#
# Usage: scripts/local-build.sh [output-dir]
#   output-dir  where to copy the finished .rpm (default: ./dist)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$REPO_ROOT/packaging/sofka.spec"
SERVICE="$REPO_ROOT/packaging/_service"
OUTDIR="${1:-$REPO_ROOT/dist}"

command -v rpmbuild >/dev/null || { echo "rpmbuild not found (zypper in rpm-build)"; exit 1; }

case "$(uname -m)" in
  x86_64)  arch_tag=x86_64 ;;
  aarch64) arch_tag=aarch64 ;;
  *) echo "unsupported host arch: $(uname -m) (sofka builds for x86_64/aarch64 only)" >&2; exit 1 ;;
esac

url=$(grep -o "<param name=\"url\">[^<]*${arch_tag}-unknown-linux-gnu\.tar\.gz</param>" "$SERVICE" \
  | sed -e 's#<param name="url">##' -e 's#</param>##' | head -1)
[ -n "$url" ] || { echo "could not find a $arch_tag download url in $SERVICE"; exit 1; }
tarball=$(basename "$url")

topdir=$(mktemp -d)
trap 'rm -rf "$topdir"' EXIT
mkdir -p "$topdir"/{SOURCES,BUILD,BUILDROOT,RPMS,SRPMS}

echo "==> fetching $tarball"
curl -fSL --progress-bar "$url" -o "$topdir/SOURCES/$tarball"

echo "==> rpmbuild -bb"
rpmbuild -bb --target "$arch_tag" --define "_topdir $topdir" "$SPEC"

mkdir -p "$OUTDIR"
find "$topdir/RPMS" -name '*.rpm' -exec cp -v {} "$OUTDIR/" \;
echo "==> done -> $OUTDIR"
