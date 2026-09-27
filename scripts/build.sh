#!/bin/bash
# Build a release package for one NanoKVM version.
#
#   scripts/build.sh 2.5.1-1
#
# TAG = <NanoKVM version>-<revision>. Checks out sipeed/NanoKVM at the NanoKVM
# version tag, applies patches/<version>/*.patch, cross-compiles NanoKVM-Server
# in the official builder image and builds the web UI.
#
# Requires: git, docker, node >= 22 (pnpm 11 is fetched via npx if missing).
# Output:   dist/nanokvm-tailscale-login-server_<TAG>.tar.gz (+ .sha256)
set -euo pipefail

NAME="nanokvm-tailscale-login-server"
UPSTREAM="${UPSTREAM:-https://github.com/sipeed/NanoKVM.git}"
BUILDER_IMAGE="${BUILDER_IMAGE:-ghcr.io/sipeed/nanokvm-builder:latest}"

TAG="${1:-}"
if ! [[ "$TAG" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)$ ]]; then
    echo "usage: $0 <nanokvm-version>-<revision>   e.g. 2.5.1-1" >&2
    exit 1
fi
NKVER="${BASH_REMATCH[1]}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="$ROOT/patches/$NKVER"
BUILD="$ROOT/build/$NKVER"
SRC="$BUILD/NanoKVM"
DIST="$ROOT/dist"

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
    echo "no patches for NanoKVM $NKVER in $PATCH_DIR" >&2
    exit 1
fi

if command -v pnpm >/dev/null 2>&1; then
    PNPM=(pnpm)
else
    PNPM=(npx -y pnpm@11)
fi

echo "::group::checkout sipeed/NanoKVM $NKVER"
rm -rf "$BUILD"
mkdir -p "$BUILD"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$NKVER" "$UPSTREAM" "$SRC"
echo "::endgroup::"

echo "::group::apply patches"
for p in "${patches[@]}"; do
    echo "  $(basename "$p")"
    git -C "$SRC" apply --whitespace=nowarn "$p"
done
echo "::endgroup::"

echo "::group::server: cross-compile NanoKVM-Server"
docker run --rm \
    -e UID="$(id -u)" -e GID="$(id -g)" \
    -e GOPATH=/tmp/go -e GOCACHE=/tmp/gocache \
    -v "$SRC":/src -w /src/server \
    "$BUILDER_IMAGE" ./build.sh
test -f "$SRC/server/NanoKVM-Server"
echo "::endgroup::"

echo "::group::web: build"
(cd "$SRC/web" && "${PNPM[@]}" install --frozen-lockfile && "${PNPM[@]}" build)
test -f "$SRC/web/dist/index.html"
echo "::endgroup::"

echo "::group::package"
PKG="$BUILD/pkg/$NAME"
mkdir -p "$PKG/server" "$PKG/files" "$DIST"
cp "$SRC/server/NanoKVM-Server" "$PKG/server/"
cp -r "$SRC/web/dist" "$PKG/server/web"
cp "$ROOT/files/tailscale-wrapper.sh" "$PKG/files/"
cp "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/LICENSE" "$PKG/"
cp -r "$PATCH_DIR" "$PKG/patches"
echo "$TAG" > "$PKG/VERSION"
echo "$NKVER" > "$PKG/NANOKVM_VERSION"
git -C "$SRC" rev-parse HEAD > "$PKG/NANOKVM_COMMIT"

ARCHIVE="$DIST/${NAME}_${TAG}.tar.gz"
tar --owner=0 --group=0 -czf "$ARCHIVE" -C "$BUILD/pkg" "$NAME"
(cd "$DIST" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
echo "::endgroup::"

ls -la "$DIST"
