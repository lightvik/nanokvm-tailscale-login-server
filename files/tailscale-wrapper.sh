#!/bin/sh
# nanokvm-tailscale-login-server wrapper
# https://github.com/lightvik/nanokvm-tailscale-login-server
#
# Stock NanoKVM-Server runs "tailscale login" / "tailscale up" without
# --login-server, so the device always joins controlplane.tailscale.com.
# If /etc/kvm/tailscale_login_server contains a URL (e.g. Headscale), this
# wrapper appends --login-server=<URL> to login/up. Empty file = stock behaviour.
REAL=/usr/bin/tailscale.real
CONF=/etc/kvm/tailscale_login_server

if [ ! -x "$REAL" ]; then
    echo "tailscale wrapper: $REAL not found" >&2
    exit 127
fi

SERVER=""
[ -r "$CONF" ] && SERVER=$(sed -n '/^[[:space:]]*[^#[:space:]]/{s/[[:space:]]//g;p;q}' "$CONF")

case "$1" in
    login|up)
        if [ -n "$SERVER" ]; then
            case " $* " in
                *" --login-server"*) ;;
                *)
                    cmd=$1
                    shift
                    exec "$REAL" "$cmd" --login-server="$SERVER" "$@"
                    ;;
            esac
        fi
        ;;
esac

exec "$REAL" "$@"
