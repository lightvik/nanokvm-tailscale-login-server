#!/bin/sh
# Remove nanokvm-tailscale-login-server from a NanoKVM.
# https://github.com/lightvik/nanokvm-tailscale-login-server
#
#   curl -fsSL https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/main/uninstall.sh | sh
#
# Options:
#   --purge       also remove /etc/kvm/tailscale_login_server and backups
#   --no-restart  do not restart NanoKVM-Server
#
# Tailscale stays logged in to the current server: use Logout / Login in the
# web UI afterwards to move the device back to Tailscale.
set -eu

NAME="nanokvm-tailscale-login-server"
STATE_DIR="/root/.$NAME"
CONF="/etc/kvm/tailscale_login_server"
APP_SERVER="/kvmapp/server"
MARKER="$APP_SERVER/.$NAME"
TS_BIN="/usr/bin/tailscale"
TS_REAL="/usr/bin/tailscale.real"

PURGE=0
RESTART=1

log() { echo "[$NAME] $*"; }
die() { echo "[$NAME] ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --purge) PURGE=1; shift ;;
        --no-restart) RESTART=0; shift ;;
        -h|--help) echo "Usage: uninstall.sh [--purge] [--no-restart]"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ "$(id -u)" = 0 ] || die "run as root"

is_elf() {
    [ "$(head -c 4 "$1" 2>/dev/null | tail -c 3)" = "ELF" ]
}

# wrapper (ours, or any non-ELF script next to tailscale.real)
if [ -f "$TS_BIN" ] && { grep -q "$NAME wrapper" "$TS_BIN" 2>/dev/null \
        || { [ -f "$TS_REAL" ] && ! is_elf "$TS_BIN"; }; }; then
    if [ -f "$TS_REAL" ]; then
        mv -f "$TS_REAL" "$TS_BIN"
        log "wrapper removed, original tailscale restored"
    else
        rm -f "$TS_BIN"
        log "wrapper removed (no real tailscale binary found)"
    fi
fi

# patched server / web
RESTORED=0
if [ -f "$MARKER" ]; then
    NKVER=$(tr -d ' \n\r' < /kvmapp/version)
    backup="$STATE_DIR/backup/$NKVER"
    if [ -f "$backup/NanoKVM-Server" ] && [ -d "$backup/web" ]; then
        cp -a "$backup/NanoKVM-Server" "$APP_SERVER/NanoKVM-Server.new"
        mv -f "$APP_SERVER/NanoKVM-Server.new" "$APP_SERVER/NanoKVM-Server"
        rm -rf "$APP_SERVER/web.old"
        mv "$APP_SERVER/web" "$APP_SERVER/web.old"
        cp -a "$backup/web" "$APP_SERVER/web"
        rm -rf "$APP_SERVER/web.old"
        rm -f "$MARKER" "$STATE_DIR/installed"
        sync
        RESTORED=1
        log "stock NanoKVM-Server and web UI restored ($NKVER)"
    else
        log "WARNING: no stock backup for NanoKVM $NKVER in $backup"
        log "reinstall the stock application via Settings > Update to remove the patched UI"
    fi
fi

if [ "$PURGE" = 1 ]; then
    rm -f "$CONF"
    rm -rf "$STATE_DIR"
    log "configuration and backups removed"
fi

if [ "$RESTORED" = 1 ]; then
    if [ "$RESTART" = 1 ]; then
        log "restarting NanoKVM-Server in 2 seconds"
        setsid sh -c 'sleep 2; /etc/init.d/S95nanokvm restart' >/dev/null 2>&1 < /dev/null &
    else
        log "restart skipped - run: /etc/init.d/S95nanokvm restart"
    fi
fi

log "done"
