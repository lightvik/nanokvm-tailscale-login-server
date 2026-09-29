# nanokvm-tailscale-login-server

[Русский](README.md)

Connect [Sipeed NanoKVM](https://github.com/sipeed/NanoKVM) to your own Tailscale control server, such as
[Headscale](https://github.com/juanfont/headscale).

Stock NanoKVM can only log in to the official Tailscale. This project extends the NanoKVM web UI: the
**Settings → Tailscale** page gets a **Login Server** field where you enter your own server's address.

## Quick install

1. NanoKVM web UI: **Settings → Tailscale → Install**.
2. On the NanoKVM as root (SSH or the `>_` web terminal):

   ```sh
   curl -fsSL \
     https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/master/install.sh \
     | sh
   ```

3. **Settings → Tailscale**: enter the URL in **Login Server** and press **Login**. Empty field — official Tailscale.

Uninstall:

```sh
curl -fsSL \
  https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/master/uninstall.sh \
  | sh
```

`--purge` also removes the saved URL and backups.

## Compatibility

Each release targets one NanoKVM version, tagged `<NanoKVM version>-<revision>`. The installer reads
`/kvmapp/version`; no matching release — error, the device is left untouched.

| NanoKVM | Release |
|---|---|
| 2.5.2 | `2.5.2-2` |
| 2.5.1 | `2.5.1-1` |

## How it works

- Patched NanoKVM-Server and web UI (`patches/<version>/`): the field, the `/api/extensions/tailscale/login-server`
  API, `--login-server` for `tailscale login/up`. The URL is stored in `/etc/kvm/tailscale_login_server`.
- `/usr/bin/tailscale` wrapper (original moved to `tailscale.real`) adds `--login-server` from the same file — in
  case a NanoKVM update brings back the stock UI.
- The stock server and web UI are backed up to `/root/.nanokvm-tailscale-login-server/backup/<version>/`;
  `uninstall.sh` restores them.

After a NanoKVM update the field disappears (the wrapper and URL stay) — install the release for the new version
with the same `curl | sh`.

## Offline install

```sh
scp nanokvm-tailscale-login-server_2.5.2-2.tar.gz root@<nanokvm>:/tmp/
ssh root@<nanokvm>
cd /tmp
gzip -dc nanokvm-tailscale-login-server_2.5.2-2.tar.gz | tar -xf -
./nanokvm-tailscale-login-server/install.sh
```

## Building and new versions

```sh
./scripts/build.sh 2.5.2-2   # Docker + Node.js 22+, output in dist/
```

New NanoKVM version: port the patch to `patches/<version>/`, check the build, push tag `<version>-1` — GitHub
Actions builds the release.

## License

GPL-3.0, same as NanoKVM. Not affiliated with Sipeed or Tailscale.
