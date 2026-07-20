# Podkop WhatsApp Real DNS Fix

[English version](README.en.md) · [Подробная ручная инструкция](docs/manual-ru.md)

Небольшое открытое исправление для OpenWrt + Podkop + sing-box, когда WhatsApp
нестабильно работает у клиентов локальной сети: сообщения остаются с иконкой
часов, медиа загружаются с перебоями или соединение периодически пропадает.

Причина в затронутой конфигурации — не маршруты Meta сами по себе, а FakeIP,
который получает клиент WhatsApp через DNS роутера. Поэтому проблема не
ограничена Wi-Fi или телефоном: она может затронуть проводные и беспроводные
устройства с любой ОС, если они используют этот OpenWrt как DNS. Исправление
возвращает реальные IP только четырём доменным суффиксам WhatsApp, сохраняя
глобальный FakeIP и маршрутизацию Podkop для всего остального.

> Это независимый community-проект, не официальный компонент Podkop. Перед
> применением обязательно выполните `check` и сохраните доступ к роутеру.

## Что меняется

- `whatsapp.com`, `whatsapp.net`, `whatsapp.biz` и `wa.me` получают реальные IP;
- правила хранятся в UCI `extraconftext`, поэтому штатный init-скрипт dnsmasq
  восстанавливает их после `podkop restart` и перезагрузки;
- существующий runtime-`confdir`, включая обычный `/tmp/dnsmasq.d`, не меняется;
- меняющиеся DNS-ответы проверяются несколько раз, и каждый полученный IPv4
  должен входить в `inet PodkopTable podkop_subnets`;
- до изменения создаётся небольшой root-only бэкап только изменяемых файлов;
- при неудачной финальной проверке скрипт автоматически откатывается.

Скрипт не отключает FakeIP глобально, не удаляет community lists, не меняет VPS,
firewall, прокси-профиль или генерируемый конфиг sing-box.

## Быстрая установка

Подключитесь к OpenWrt по SSH под `root`. Сначала можно скачать и просмотреть
установщик:

```sh
wget -O /tmp/install.sh \
  https://github.com/Pingkazama/podkop-whatsapp-real-dns/releases/latest/download/install.sh

sed -n '1,240p' /tmp/install.sh
sh /tmp/install.sh
```

Или одной командой:

```sh
wget -qO /tmp/install.sh https://github.com/Pingkazama/podkop-whatsapp-real-dns/releases/latest/download/install.sh && sh /tmp/install.sh
```

Установщик сверяет SHA256 и атомарно заменяет инструмент в
`/usr/bin/whatsapp-real-dns-fix`. Он **не применяет DNS-изменения сам**, не
удаляет рабочую DNS-конфигурацию и не создаёт на overlay накапливающиеся копии
старого бинарника. Если финальная замена не удалась, прежний инструмент остаётся
на месте.

## Обновление v1.0.0/v1.0.1/v1.0.2

Удалять раннюю версию перед установкой новой не нужно. Повторно запустите
актуальный установщик, затем выполните:

```sh
whatsapp-real-dns-fix check
whatsapp-real-dns-fix apply
whatsapp-real-dns-fix status
```

`check` распознаёт managed state v2/v3/v4, проверяет резолвер, маршруты и FakeIP
и печатает `upgrade:ready`. `apply` сначала сохраняет исходный DHCP state и
прежний файл правила в минимальный бэкап, затем переносит правила в
`extraconftext` и мигрирует конфигурацию в state v5. Старый управляемый
`/etc/config/dnsmasq.d` удаляется после бэкапа, а обычный runtime-каталог
`/tmp/dnsmasq.d` остаётся без изменений. Неизвестная версия state
останавливается до записи файлов с ошибкой
`unsupported_managed_state_version`.

## Проверка и применение

```sh
whatsapp-real-dns-fix check
```

Продолжайте только если увидели:

```text
preflight:ok
real_dns_answer:available
all_real_ipv4_routes:podkop
sing_box_fakeip_engine:active
```

Если стандартный контрольный DNS sing-box `127.0.0.42` не отвечает, `check`
теперь останавливается до любых изменений с ошибкой
`fakeip_control_dns_failed_*`. Для подтверждённой нестандартной схемы можно
указать другой локальный FakeIP DNS одинаково в обеих командах:

```sh
FAKE_DNS=127.0.0.54 whatsapp-real-dns-fix check
FAKE_DNS=127.0.0.54 whatsapp-real-dns-fix apply
```

Выбранный адрес сохраняется в managed state. Не используйте здесь обычный
публичный DNS — контрольный адрес должен возвращать FakeIP.

Применение:

```sh
whatsapp-real-dns-fix apply
```

Проверка состояния и откат:

```sh
whatsapp-real-dns-fix status
whatsapp-real-dns-fix rollback
```

При неудачном postcheck скрипт отдельно указывает сбой dnsmasq и/или FakeIP.
`rollback:verified` означает, что исходная конфигурация восстановлена и dnsmasq
проверен. Ошибка с суффиксом `_rollback_failed_manual_recovery_required`
требует остановиться и выполнить ручное восстановление из показанного бэкапа.
Автоматический `apply` не запускает `sysupgrade -b`: полный архив на небольшом
overlay мог включить крупные файлы из `/root` и заполнить свободное место.

После успешного `apply` обновите DNS-состояние на проблемном устройстве —
например, переподключите сеть или перезапустите приложение — и проверьте текст,
изображение, голосовой и видеозвонок. Перезагрузка роутера обычно не нужна.

## Требования

- OpenWrt с `dnsmasq`, UCI и `nftables`;
- init-скрипт dnsmasq с поддержкой UCI `extraconftext`;
- запущенные Podkop и sing-box;
- активный набор `inet PodkopTable podkop_subnets`;
- IPv4 DNS в `podkop.settings.dns_server` или
  `podkop.settings.bootstrap_dns_server`;
- маршрут текущего контрольного адреса WhatsApp уже покрыт community list,
  например Meta.

Если проверка сообщает `no_safe_real_dns_resolver` или отсутствие IP в
`podkop_subnets`, ничего не применяйте: сначала исправьте DNS/списки Podkop.

## Установка конкретной версии

```sh
VERSION=v1.0.3 sh /tmp/install.sh
```

Хеши релизных файлов публикуются в `SHA256SUMS`.

## Как это устроено

```text
Клиент в LAN -> dnsmasq -> реальный DNS только для WhatsApp
                         -> настоящий IP -> podkop_subnets -> прокси

Остальные домены -> DNS-вход sing-box -> FakeIP -> обычная логика Podkop
```

Прямое добавление правил в `dhcp.@dnsmasq[0].server` ненадёжно: Podkop может
пересобрать этот UCI-список при перезапуске. Поэтому правила хранятся в
`dhcp.@dnsmasq[0].extraconftext`; штатный init-скрипт OpenWrt разворачивает их в
`extraconfig.conf` внутри своего runtime-`confdir`. Инструмент не заменяет
существующий `confdir`.

Полное объяснение, ручная установка, диагностика и ручной откат находятся в
[инструкции для начинающих](docs/manual-ru.md).

## Поддержка

Перед созданием issue приложите обезличенный вывод:

```sh
whatsapp-real-dns-fix status
```

Не публикуйте пароли, ключи, ссылки подписок, конфиги прокси, архивы
`sysupgrade` или полные дампы трафика.

## Лицензия

[MIT](LICENSE)
