# AGENTS.md

Guide for AI agents working on this repository. The main recurring task is **adding support for a new
NanoKVM release** — see the step-by-step procedure below.

## What this project is

A patch for [sipeed/NanoKVM](https://github.com/sipeed/NanoKVM) that adds a "Login Server" field to
**Settings → Tailscale** in the NanoKVM web UI, so the device can log in to Headscale (or another
compatible control server) instead of `controlplane.tailscale.com`. We ship a patched `NanoKVM-Server`
binary + web UI per NanoKVM version, plus an install script run on the device via `curl | sh`.

## Layout

```
patches/<nanokvm-version>/*.patch   git format-patch against sipeed/NanoKVM tag <nanokvm-version>
files/tailscale-wrapper.sh          /usr/bin/tailscale wrapper (fallback after NanoKVM OTA)
install.sh / uninstall.sh           run ON the device (BusyBox ash, POSIX sh only)
scripts/build.sh <tag>              builds dist/nanokvm-tailscale-login-server_<tag>.tar.gz
.github/workflows/build.yml         shellcheck + build every patches/* dir (artifact only)
.github/workflows/release.yml       on tag push: build + publish GitHub release
README.md (ru, default), README.en.md
```

## Versioning — the core invariant

- Release tag = `<NanoKVM version>-<revision>`, e.g. `2.5.1-1`. NanoKVM version = the sipeed/NanoKVM git
  tag = the content of `/kvmapp/version` on the device.
- A release contains binaries built from **exactly** that upstream tag. Never ship a build of one
  NanoKVM version for another.
- `install.sh` reads `/kvmapp/version` and installs the newest `<version>-N` release; if there is none it
  **fails without changing anything**. There is no `--force` and no wrapper-only mode — keep it that way.
- New NanoKVM version → revision `-1`. A fix for an already supported version → next revision (`2.5.1-2`).

## Product decisions (do not change without the maintainer asking)

- The Login Server field is **empty by default** = official Tailscale. Empty value → no `--login-server`.
- The server is set **only in the web UI**. `install.sh` must not take a server URL option.
- `install.sh --tag` exists but is not the default path; it must match the device's NanoKVM version.
- The URL is stored in `/etc/kvm/tailscale_login_server` (comment lines allowed, first non-comment line
  is the URL). Both the patched server and the wrapper read this file — keep the format compatible.
- Accepted URLs: `^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$`, trailing `/` stripped.
  The value goes into `sh -c`, so never loosen the charset.

## What the patch changes (reference: patches/2.5.1)

Backend (`server/`):
- `service/extensions/tailscale/login_server.go` (new): read/validate/write the config file,
  `loginServerArg()`; `login_server_test.go` — URL validation tests.
- `service/extensions/tailscale/cli.go`: append `loginServerArg()` to `tailscale up` and `tailscale login`.
- `service/extensions/tailscale/service.go`: `GetLoginServer`/`SetLoginServer` handlers, `loginServer` in
  status, `Uninstall` also removes `/usr/bin/tailscale.real`.
- `router/extensions.go`: `GET/POST /api/extensions/tailscale/login-server` (inside the admin-only group).
- `proto/tailscale.go`: request/response types, `LoginServer` in `GetTailscaleStatusRsp`.

Web (`web/src/`):
- `api/extensions/tailscale.ts`: `getLoginServer`, `setLoginServer`.
- `pages/desktop/menu/settings/tailscale/login.tsx`: the input above the Login button; saves the value,
  then calls login. `device.tsx`: shows the server row. `types.ts`: `loginServer?`.
- `i18n/locales/en.ts`, `ru.ts`: `settings.tailscale.loginServer.*` (other locales fall back to `en`).

## Procedure: support a new NanoKVM version

Example: upstream released `2.6.0`, previous supported version is `2.5.1`.

1. Check the release exists: `gh api repos/sipeed/NanoKVM/releases --jq '.[0:5][]|.tag_name'`.
   Use the plain numeric tag (`2.6.0`), not `nanokvm@…` or `v1.x` (legacy).
2. Port the patch:
   ```sh
   git clone https://github.com/sipeed/NanoKVM.git /tmp/NanoKVM && cd /tmp/NanoKVM
   git checkout -b tailscale-login-server 2.6.0
   git am -3 <repo>/patches/2.5.1/*.patch      # resolve conflicts if any, then git am --continue
   ```
   Before resolving, read upstream changes in the touched files:
   `git diff 2.5.1 2.6.0 -- server/service/extensions/tailscale server/router/extensions.go server/proto/tailscale.go web/src/pages/desktop/menu/settings/tailscale web/src/api/extensions/tailscale.ts`.
   Watch for: renamed/moved files, changed `tailscale login/up` command strings in `cli.go`, new fields in
   the status proto, i18n structure changes, new UI components. Keep the patch minimal and in upstream style.
3. Verify the port in `/tmp/NanoKVM`:
   ```sh
   (cd server && gofmt -l service/extensions/tailscale && go vet ./service/extensions/tailscale/ && go test ./service/extensions/tailscale/)
   (cd web && npx -y pnpm@11 install --frozen-lockfile && npx -y pnpm@11 build \
     && npx -y pnpm@11 exec eslint src/pages/desktop/menu/settings/tailscale src/api/extensions \
     && npx -y pnpm@11 exec prettier --check src/pages/desktop/menu/settings/tailscale src/api/extensions/tailscale.ts)
   ```
   Use the pnpm major from upstream `.github/workflows/package.yml` if it changed.
4. Export as a single commit:
   ```sh
   mkdir -p <repo>/patches/2.6.0
   git format-patch -1 HEAD --no-signature -o <repo>/patches/2.6.0/
   ```
   Keep old `patches/<version>/` directories — each supported version stays buildable.
5. Full build: `./scripts/build.sh 2.6.0-1` (needs Docker; pulls `ghcr.io/sipeed/nanokvm-builder`, ~9 GB).
   Sanity-check the binary against the stock one if available: same `go1.x`, `GOEXPERIMENT=boringcrypto`,
   `CGO_CFLAGS`, `RUNPATH [$ORIGIN/dl_lib]`, `NEEDED libkvm.so` (`strings`, `readelf -d`).
   If upstream changed `server/build.sh`, the builder image or the web build, update `scripts/build.sh`.
6. If `install.sh` assumptions changed upstream (paths `/kvmapp/server/{NanoKVM-Server,web}`,
   `/etc/init.d/S95nanokvm restart`, `/usr/bin/tailscale`, `/usr/sbin/tailscaled`,
   `/etc/init.d/S98tailscaled`), update the scripts — and keep them working for older versions.
7. Update the compatibility table in `README.md` and `README.en.md`.
8. Open a PR or push to `master`; the Build workflow must pass. Then, **only when the maintainer says so**,
   tag and push: `git tag -a 2.6.0-1 -m "2.6.0-1" && git push origin 2.6.0-1` → Release workflow publishes.
9. Device test (maintainer's test NanoKVM on the new version): Settings → Tailscale → Install, then
   `curl | sh` from the README, set a server in the field, Login, check the link points to that server.
   Then `uninstall.sh` must restore the stock server (compare sha256 with the backup).

## Device environment (for install.sh / uninstall.sh / wrapper)

- BusyBox ash, riscv64, musl. POSIX sh only: no bashisms, no `jq`. `tar` has **no `-z`** — use
  `gzip -dc file | tar -xf -`. `curl` (OpenSSL), `sha256sum`, `setsid` are available.
- NanoKVM-Server runs from a copy in `/tmp/server`; restart via `/etc/init.d/S95nanokvm restart`. The
  restart kills the web terminal, so installers restart **detached** with `setsid … &` as the last step.
- NanoKVM OTA replaces `/kvmapp` (our server and web) but not `/usr/bin` or `/etc/kvm` — that is why the
  wrapper exists. Backups live in `/root/.nanokvm-tailscale-login-server/backup/<version>/`.
- The stock web UI "Install Tailscale" moves the real binary to `/usr/bin/tailscale`; "Uninstall" deletes it.
- Lint: `shellcheck -s sh install.sh uninstall.sh files/tailscale-wrapper.sh && shellcheck scripts/build.sh`;
  workflows: `actionlint`.

## Rules

- Do not touch anyone's Headscale/Tailscale servers (registering, tagging, deleting nodes) — testing stops
  at getting a login link; the maintainer handles the server side.
- Do not tag/publish releases or change the device's firmware without explicit instruction.
- Commit style: short imperative subject (`docs: …`, `ci: …`, `install.sh: …`). Default branch: `master`.
- License GPL-3.0 (derived from NanoKVM); keep `LICENSE` and upstream attribution.
