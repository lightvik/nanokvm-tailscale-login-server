#!/bin/sh
# Install nanokvm-tailscale-login-server on a NanoKVM.
# https://github.com/lightvik/nanokvm-tailscale-login-server
#
#   curl -fsSL https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/master/install.sh | sh
#
# The login server itself is set in the web UI: Settings > Tailscale > Login Server.
#
# The release is picked by the NanoKVM version installed on the device
# (/kvmapp/version): 2.5.1 -> the newest 2.5.1-N release. If there is no
# release for that version, the installer stops without changing anything.
#
# Options:
#   --tag TAG           install a specific revision for this NanoKVM version (e.g. 2.5.1-1)
#   --no-restart        do not restart NanoKVM-Server after installing
set -eu

REPO="lightvik/nanokvm-tailscale-login-server"
NAME="nanokvm-tailscale-login-server"
STATE_DIR="/root/.$NAME"
CONF="/etc/kvm/tailscale_login_server"
APP_SERVER="/kvmapp/server"
MARKER="$APP_SERVER/.$NAME"
TS_BIN="/usr/bin/tailscale"
TS_REAL="/usr/bin/tailscale.real"

TAG=""
RESTART=1

log() { echo "[$NAME] $*"; }
die() { echo "[$NAME] ERROR: $*" >&2; exit 1; }

usage() {
    cat <<USAGE
Usage: install.sh [options]
  --tag TAG           install a specific revision for this NanoKVM version (e.g. 2.5.1-1)
  --no-restart        do not restart NanoKVM-Server after installing
USAGE
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) [ $# -ge 2 ] || die "--tag needs a value"; TAG=$2; shift 2 ;;
        --tag=*) TAG=${1#*=}; shift ;;
        --no-restart) RESTART=0; shift ;;
        -h|--help) usage ;;
        *) die "unknown option: $1" ;;
    esac
done

[ "$(id -u)" = 0 ] || die "run as root"
[ -f /kvmapp/version ] || die "/kvmapp/version not found - is this a NanoKVM?"
NKVER=$(tr -d ' \n\r' < /kvmapp/version)
log "NanoKVM application version: $NKVER"

TMP=$(mktemp -d /tmp/$NAME.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM

# Package directory: the extracted release next to this script (offline
# install), otherwise downloaded from GitHub releases.
PKG=""
SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || SELF_DIR=""
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/NANOKVM_VERSION" ]; then
    PKG=$SELF_DIR
fi

fetch() {
    curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
}

NKVER_RE="^$(echo "$NKVER" | sed 's/\./\\./g')-[0-9]+\$"

resolve_tag() {
    fetch "https://api.github.com/repos/$REPO/releases?per_page=100" "$TMP/releases.json" \
        || die "failed to query GitHub releases"
    grep -o '"tag_name": *"[^"]*"' "$TMP/releases.json" \
        | sed 's/.*"\([^"]*\)"$/\1/' > "$TMP/tags"

    tag=$(grep -E "$NKVER_RE" "$TMP/tags" | sort -t- -k2 -n | tail -n 1)
    if [ -z "$tag" ]; then
        supported=$(sed -n 's/^\([0-9]*\.[0-9]*\.[0-9]*\)-[0-9]*$/\1/p' "$TMP/tags" | sort -u | tr '\n' ' ' | sed 's/ $//')
        die "no compatible release for NanoKVM $NKVER (supported: ${supported:-none}). See https://github.com/$REPO/releases"
    fi
    echo "$tag"
}

download_package() {
    if [ -n "$TAG" ]; then
        echo "$TAG" | grep -Eq "$NKVER_RE" \
            || die "release $TAG does not match NanoKVM $NKVER on this device"
    else
        TAG=$(resolve_tag)
    fi

    file="$NAME""_$TAG.tar.gz"
    base="https://github.com/$REPO/releases/download/$TAG"
    log "downloading $file"
    fetch "$base/$file" "$TMP/$file" || die "download failed: $base/$file"
    fetch "$base/$file.sha256" "$TMP/$file.sha256" || die "download failed: $base/$file.sha256"

    expected=$(awk '{print $1}' "$TMP/$file.sha256")
    actual=$(sha256sum "$TMP/$file" | awk '{print $1}')
    [ "$expected" = "$actual" ] || die "checksum mismatch for $file"

    gzip -dc "$TMP/$file" | tar -xf - -C "$TMP"
    PKG="$TMP/$NAME"
    [ -f "$PKG/NANOKVM_VERSION" ] || die "invalid package"
}

is_elf() {
    [ "$(head -c 4 "$1" 2>/dev/null | tail -c 3)" = "ELF" ]
}

install_wrapper() {
    src="$1"
    # any non-ELF /usr/bin/tailscale next to tailscale.real is a wrapper
    # (ours or a hand-made one) - replace it, never move it over the real binary
    if [ -f "$TS_BIN" ] && { grep -q "$NAME wrapper" "$TS_BIN" 2>/dev/null \
            || { [ -f "$TS_REAL" ] && ! is_elf "$TS_BIN"; }; }; then
        cp "$src" "$TS_BIN.new" && chmod 755 "$TS_BIN.new" && mv -f "$TS_BIN.new" "$TS_BIN"
        log "wrapper updated: $TS_BIN"
    elif [ -f "$TS_BIN" ]; then
        is_elf "$TS_BIN" || die "$TS_BIN is not an ELF binary - refusing to wrap it"
        mv -f "$TS_BIN" "$TS_REAL"
        cp "$src" "$TS_BIN" && chmod 755 "$TS_BIN"
        log "wrapper installed: $TS_BIN (real binary: $TS_REAL)"
    else
        log "tailscale is not installed yet - wrapper skipped"
        log "(re-run this installer after installing Tailscale in the web UI)"
    fi
}

# empty config = official Tailscale server; an existing value is kept
write_conf() {
    if [ ! -f "$CONF" ]; then
        echo "# Custom Tailscale control server (e.g. Headscale). Empty = Tailscale default." > "$CONF"
    fi
}

install_ui() {
    pkg_nkver=$(tr -d ' \n\r' < "$PKG/NANOKVM_VERSION")
    pkg_tag=$(tr -d ' \n\r' < "$PKG/VERSION")
    if [ "$pkg_nkver" != "$NKVER" ]; then
        die "release $pkg_tag is built for NanoKVM $pkg_nkver, this device runs $NKVER"
    fi

    # Back up the stock server once per NanoKVM version, never our own build.
    backup="$STATE_DIR/backup/$NKVER"
    if [ ! -f "$MARKER" ]; then
        log "backing up stock NanoKVM-Server and web to $backup"
        rm -rf "$backup" && mkdir -p "$backup"
        cp -a "$APP_SERVER/NanoKVM-Server" "$backup/"
        cp -a "$APP_SERVER/web" "$backup/"
    elif [ ! -d "$backup" ]; then
        log "WARNING: patched build already installed and no stock backup for $NKVER"
    fi

    cp "$PKG/server/NanoKVM-Server" "$APP_SERVER/NanoKVM-Server.new"
    chmod 755 "$APP_SERVER/NanoKVM-Server.new"

    rm -rf "$APP_SERVER/web.new"
    cp -r "$PKG/server/web" "$APP_SERVER/web.new"
    # keep the custom logo handled by S95nanokvm (/boot/logo.ico)
    for ico in sipeed.ico original.ico; do
        [ -f "$APP_SERVER/web/$ico" ] && cp -a "$APP_SERVER/web/$ico" "$APP_SERVER/web.new/$ico"
    done

    mv -f "$APP_SERVER/NanoKVM-Server.new" "$APP_SERVER/NanoKVM-Server"
    rm -rf "$APP_SERVER/web.old"
    mv "$APP_SERVER/web" "$APP_SERVER/web.old"
    mv "$APP_SERVER/web.new" "$APP_SERVER/web"
    rm -rf "$APP_SERVER/web.old"

    echo "$pkg_tag" > "$MARKER"
    mkdir -p "$STATE_DIR"
    echo "$pkg_tag" > "$STATE_DIR/installed"
    sync
    log "patched NanoKVM-Server and web UI installed ($pkg_tag)"
}

restart_server() {
    if [ "$RESTART" != 1 ]; then
        log "restart skipped - run: /etc/init.d/S95nanokvm restart"
        return
    fi
    # Detached: when run from the web terminal, the restart kills this shell.
    log "restarting NanoKVM-Server in 2 seconds (the web UI will reconnect)"
    setsid sh -c 'sleep 2; /etc/init.d/S95nanokvm restart' >/dev/null 2>&1 < /dev/null &
}

if [ -z "$PKG" ]; then
    download_package
fi

install_ui
write_conf
install_wrapper "$PKG/files/tailscale-wrapper.sh"
restart_server

log "done"
