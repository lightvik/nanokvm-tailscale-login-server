# nanokvm-tailscale-login-server

[English version](README.md)

Добавляет поле **«Сервер входа»** на страницу Tailscale в веб-интерфейсе
[Sipeed NanoKVM](https://github.com/sipeed/NanoKVM): устройство можно подключить к
[Headscale](https://github.com/juanfont/headscale) или другому совместимому control server вместо
`controlplane.tailscale.com`.

Штатный NanoKVM-Server вызывает `tailscale login` / `tailscale up` без `--login-server`, а
`tailscale login` всегда начинает с пустого профиля — поэтому даже вручную настроенный сервер
сбрасывается на Tailscale при следующем нажатии **«Войти»** в веб-интерфейсе.

Проект не связан с Sipeed и Tailscale.

## Совместимость

Каждый релиз собран ровно под одну версию приложения NanoKVM. Теги релизов —
`<версия NanoKVM>-<ревизия>`:

| NanoKVM (`/kvmapp/version`) | Релиз |
|---|---|
| 2.5.1 | `2.5.1-1` |

Инсталлятор читает `/kvmapp/version` на устройстве и ставит свежую ревизию под эту версию. Если
подходящего релиза нет — завершается с ошибкой, ничего не меняя.

## Установка

1. В веб-интерфейсе NanoKVM установите Tailscale как обычно: **Настройки → Tailscale → Установить**.
2. На NanoKVM под root (SSH или веб-терминал `>_` в тулбаре):

   ```sh
   curl -fsSL https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/main/install.sh | sh
   ```

   В конце NanoKVM-Server перезапускается, веб-интерфейс переподключится через несколько секунд.

3. **Настройки → Tailscale**: укажите URL в поле **«Сервер входа»** (например
   `https://headscale.example.com`) и нажмите **«Войти»**. Пустое поле — официальный сервер Tailscale.

С Headscale ссылка входа ведёт на страницу регистрации — подтвердите ноду на стороне Headscale
(`headscale auth register …` или ваша админка).

Сменить сервер позже: **«Выйти»**, изменить поле, **«Войти»**.

### Офлайн-установка

Скачайте `nanokvm-tailscale-login-server_<tag>.tar.gz` из [Releases](../../releases), скопируйте на
устройство и запустите вложенный инсталлятор (в BusyBox `tar` нет `-z`):

```sh
scp nanokvm-tailscale-login-server_2.5.1-1.tar.gz root@<nanokvm>:/tmp/
ssh root@<nanokvm>
cd /tmp && gzip -dc nanokvm-tailscale-login-server_2.5.1-1.tar.gz | tar -xf -
./nanokvm-tailscale-login-server/install.sh
```

### Опции

`install.sh --tag 2.5.1-1` — конкретная ревизия (должна соответствовать версии NanoKVM на устройстве),
`--no-restart` — не перезапускать NanoKVM-Server.

## Удаление

```sh
curl -fsSL https://raw.githubusercontent.com/lightvik/nanokvm-tailscale-login-server/main/uninstall.sh | sh
```

Восстанавливает штатные NanoKVM-Server и веб-интерфейс из бэкапа, сделанного при установке, и убирает
wrapper. `--purge` дополнительно удаляет сохранённый URL и бэкапы. Tailscale остаётся залогинен на
текущем сервере — потом **«Выйти» / «Войти»**, чтобы вернуться на Tailscale.

## Как это работает

- **Патченные NanoKVM-Server и веб** (`patches/<версия>/`): поле «Сервер входа», API
  `GET/POST /api/extensions/tailscale/login-server` (только admin), сервер в карточке устройства.
  URL хранится в `/etc/kvm/tailscale_login_server` и добавляется к `tailscale login/up` как
  `--login-server`. Принимаются только `http(s)://хост[:порт][/путь]`.
- **Wrapper `/usr/bin/tailscale`** (`files/tailscale-wrapper.sh`): настоящий бинарь переносится в
  `/usr/bin/tailscale.real`, wrapper добавляет `--login-server` из того же файла. Держит устройство на
  вашем сервере, даже когда обновление NanoKVM вернуло штатный интерфейс.
- **Бэкап**: штатные `/kvmapp/server/NanoKVM-Server` и `/kvmapp/server/web` сохраняются в
  `/root/.nanokvm-tailscale-login-server/backup/<версия>/`.

## Обновления NanoKVM

Обновление NanoKVM (**Настройки → Проверить обновления**) перезаписывает `/kvmapp`, то есть патченный
интерфейс. Wrapper и сохранённый URL остаются — Tailscale продолжит ходить на ваш сервер, — но поле
«Сервер входа» пропадёт, пока не выйдет релиз под новую версию NanoKVM (ставится тем же `curl | sh`).

Если удалить Tailscale из веб-интерфейса при штатном сервере — установите Tailscale заново и ещё раз
запустите `install.sh`, чтобы вернуть wrapper.

## Сборка

Нужны Docker и Node.js 22+:

```sh
./scripts/build.sh 2.5.1-1
```

Берёт `sipeed/NanoKVM` на теге версии NanoKVM, накладывает `patches/2.5.1/*.patch`, собирает
NanoKVM-Server в официальном образе `ghcr.io/sipeed/nanokvm-builder` (тот же toolchain, BoringCrypto и
RPATH, что у апстрим-релиза) и веб-интерфейс. Результат — в `dist/`.

## Поддержка новой версии NanoKVM

1. Перенести патч: `sipeed/NanoKVM` на новом теге, наложить предыдущий патч, разрешить конфликты,
   закоммитить и `git format-patch -1 -o patches/<новая-версия>/`.
2. Проверить локально: `./scripts/build.sh <новая-версия>-1`.
3. Запушить тег `<новая-версия>-1` — workflow Release соберёт и опубликует релиз.

Исправления для уже поддерживаемой версии — следующая ревизия (`2.5.1-2`).

## Лицензия

GPL-3.0, как и NanoKVM. Релизы содержат бинарники, собранные из `sipeed/NanoKVM` с патчами из этого
репозитория; точный коммит апстрима записан в `NANOKVM_COMMIT` внутри архива релиза.
