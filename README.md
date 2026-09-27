# nanokvm-tailscale-login-server

[Русская версия](README.ru.md)

Adds a **Login Server** field to the Tailscale page of the [Sipeed NanoKVM](https://github.com/sipeed/NanoKVM)
web UI, so the device can join [Headscale](https://github.com/juanfont/headscale) or any other
Tailscale-compatible control server instead of `controlplane.tailscale.com`.

The stock NanoKVM-Server runs `tailscale login` / `tailscale up` without `--login-server`, and
`tailscale login` always starts from an empty profile — so even a manually configured server is reset
to Tailscale the next time you press **Login** in the web UI.

Not affiliated with Sipeed or Tailscale.

## Compatibility

Each release is built for exactly one NanoKVM application version. Release tags are
`<NanoKVM version>-<revision>`:

| NanoKVM (`/kvmapp/version`) | Release |
|---|---|
| 2.5.1 | `2.5.1-1` |

The installer reads `/kvmapp/version` on the device and installs the newest revision built for that
version. If there is no matching release, it stops with an error and changes nothing.

## Install

1. In the NanoKVM web UI install Tailscale as usual: **Settings → Tailscale → Install**.
2. On the NanoKVM, as root (SSH, or the web terminal `>_` in the toolbar):

   ```sh
   curl -fsSL https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/main/install.sh | sh
   ```

   NanoKVM-Server restarts at the end; the web UI reconnects in a few seconds.

3. **Settings → Tailscale**: enter the server URL in **Login Server** (e.g. `https://headscale.example.com`)
   and press **Login**. Leave the field empty to use the official Tailscale server.

With Headscale the login link opens a registration page — approve the node on the Headscale side
(`headscale auth register …`, or your admin UI).

To switch servers later: **Logout**, change the field, **Login**.

### Offline install

Download `nanokvm-tailscale-login-server_<tag>.tar.gz` from [Releases](../../releases), copy it to the
device and run the bundled installer (BusyBox `tar` has no `-z`):

```sh
scp nanokvm-tailscale-login-server_2.5.1-1.tar.gz root@<nanokvm>:/tmp/
ssh root@<nanokvm>
cd /tmp && gzip -dc nanokvm-tailscale-login-server_2.5.1-1.tar.gz | tar -xf -
./nanokvm-tailscale-login-server/install.sh
```

### Options

`install.sh --tag 2.5.1-1` installs a specific revision (must match the device's NanoKVM version),
`--no-restart` skips the NanoKVM-Server restart.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/main/uninstall.sh | sh
```

Restores the stock NanoKVM-Server and web UI from the backup made at install time and removes the
wrapper. `--purge` also deletes the saved server URL and the backups. Tailscale stays logged in to the
current server — use **Logout / Login** afterwards to move back to Tailscale.

## How it works

- **Patched NanoKVM-Server and web UI** (`patches/<version>/`): the Login Server field, the
  `GET/POST /api/extensions/tailscale/login-server` API (admin only), the server shown on the device card.
  The URL is stored in `/etc/kvm/tailscale_login_server` and appended to `tailscale login/up` as
  `--login-server`. Only plain `http(s)://host[:port][/path]` URLs are accepted.
- **`/usr/bin/tailscale` wrapper** (`files/tailscale-wrapper.sh`): the real binary is moved to
  `/usr/bin/tailscale.real`; the wrapper adds `--login-server` from the same file. It keeps the device on
  your server even after a NanoKVM update replaces the patched UI with the stock one.
- **Backup**: the stock `/kvmapp/server/NanoKVM-Server` and `/kvmapp/server/web` are saved to
  `/root/.nanokvm-tailscale-login-server/backup/<version>/`.

## NanoKVM updates

A NanoKVM update (**Settings → Check for Updates**) replaces `/kvmapp`, i.e. the patched UI. The wrapper
and the saved URL survive, so Tailscale keeps using your server, but the Login Server field disappears
until a release for the new NanoKVM version is published and installed with the same `curl | sh`.

If you uninstall Tailscale from the web UI with the stock server, reinstall Tailscale and run
`install.sh` again to restore the wrapper.

## Building

Requires Docker and Node.js 22+:

```sh
./scripts/build.sh 2.5.1-1
```

Checks out `sipeed/NanoKVM` at the NanoKVM tag, applies `patches/2.5.1/*.patch`, cross-compiles
NanoKVM-Server in the official `ghcr.io/sipeed/nanokvm-builder` image (same toolchain, BoringCrypto and
RPATH as the upstream release) and builds the web UI. Output goes to `dist/`.

## Supporting a new NanoKVM version

1. Port the patch: check out `sipeed/NanoKVM` at the new tag, apply the previous patch, fix conflicts,
   commit and `git format-patch -1 -o patches/<new-version>/`.
2. Test locally with `./scripts/build.sh <new-version>-1`.
3. Push a tag `<new-version>-1`; the Release workflow builds and publishes it.

Fixes for an already supported NanoKVM version get the next revision (`2.5.1-2`).

## License

GPL-3.0, same as NanoKVM. Releases contain binaries built from `sipeed/NanoKVM` plus the patches in this
repository; the exact upstream commit is recorded in `NANOKVM_COMMIT` inside each release archive.
