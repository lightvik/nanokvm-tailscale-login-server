# nanokvm-tailscale-login-server

[English](README.en.md)

Поле **«Сервер входа»** на странице Tailscale в веб-интерфейсе [Sipeed NanoKVM](https://github.com/sipeed/NanoKVM) —
подключение к [Headscale](https://github.com/juanfont/headscale) или другому совместимому серверу вместо Tailscale.

## Быстрая установка

1. Веб-интерфейс NanoKVM: **Настройки → Tailscale → Установить**.
2. На NanoKVM под root (SSH или веб-терминал `>_`):

   ```sh
   R=https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/main
   curl -fsSL $R/install.sh | sh
   ```

3. **Настройки → Tailscale**: укажите URL в поле «Сервер входа» и нажмите «Войти». Пустое поле — официальный Tailscale.

Удаление:

```sh
R=https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/main
curl -fsSL $R/uninstall.sh | sh
```

`--purge` дополнительно удаляет сохранённый URL и бэкапы.

## Совместимость

Релиз собирается под конкретную версию NanoKVM, тег — `<версия NanoKVM>-<ревизия>`. Инсталлятор берёт версию из
`/kvmapp/version`; нет подходящего релиза — ошибка, устройство не меняется.

| NanoKVM | Релиз |
|---|---|
| 2.5.1 | `2.5.1-1` |

## Как это работает

- Патченные NanoKVM-Server и веб (`patches/<версия>/`): поле, API `/api/extensions/tailscale/login-server`,
  передача `--login-server` в `tailscale login/up`. URL хранится в `/etc/kvm/tailscale_login_server`.
- Wrapper `/usr/bin/tailscale` (оригинал — `tailscale.real`) добавляет `--login-server` из того же файла — на случай,
  если обновление NanoKVM вернуло штатный интерфейс.
- Штатные сервер и веб сохраняются в `/root/.nanokvm-tailscale-login-server/backup/<версия>/`, `uninstall.sh` их
  восстанавливает.

После обновления NanoKVM поле пропадает (wrapper и URL остаются) — поставьте релиз под новую версию тем же `curl | sh`.

## Офлайн-установка

```sh
F=nanokvm-tailscale-login-server_2.5.1-1.tar.gz
scp $F root@<nanokvm>:/tmp/
ssh root@<nanokvm> "cd /tmp && gzip -dc $F | tar -xf - \
  && ./nanokvm-tailscale-login-server/install.sh"
```

## Сборка и новые версии

```sh
./scripts/build.sh 2.5.1-1   # Docker + Node.js 22+, результат в dist/
```

Новая версия NanoKVM: перенести патч в `patches/<версия>/`, проверить сборку, запушить тег `<версия>-1` — релиз
соберёт GitHub Actions.

## Лицензия

GPL-3.0, как и NanoKVM. Проект не связан с Sipeed и Tailscale.
