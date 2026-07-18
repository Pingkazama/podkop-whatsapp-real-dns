# Podkop WhatsApp Real DNS Fix

[English version](README.en.md) · [Подробная ручная инструкция](docs/manual-ru.md)

Небольшое открытое исправление для OpenWrt + Podkop + sing-box, когда WhatsApp
за Wi-Fi нестабильно отправляет сообщения, оставляет значок часов или оживает
только после переключения между Wi-Fi и мобильной сетью.

Причина в затронутой конфигурации — не маршруты Meta сами по себе, а FakeIP,
который получает мобильный клиент WhatsApp. Исправление возвращает реальные IP
только четырём доменным суффиксам WhatsApp, сохраняя глобальный FakeIP и
маршрутизацию Podkop для всего остального.

> Это независимый community-проект, не официальный компонент Podkop. Перед
> применением обязательно выполните `check` и сохраните доступ к роутеру.

## Что меняется

- `whatsapp.com`, `whatsapp.net`, `whatsapp.biz` и `wa.me` получают реальные IP;
- правила хранятся отдельно в `/etc/config/dnsmasq.d`, поэтому переживают
  `podkop restart`;
- каждый IPv4 текущего контрольного DNS-ответа проверяется в
  `inet PodkopTable podkop_subnets`;
- до изменения создаются конфигурационный и `sysupgrade`-бэкапы;
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

Установщик сверяет SHA256 и копирует инструмент в
`/usr/bin/whatsapp-real-dns-fix`. Он **не применяет DNS-изменения сам**.

## Проверка и применение

```sh
whatsapp-real-dns-fix check
```

Продолжайте только если увидели:

```text
preflight:ok
real_dns_answer:available
all_real_ipv4_routes:podkop
```

Применение:

```sh
whatsapp-real-dns-fix apply
```

Проверка состояния и откат:

```sh
whatsapp-real-dns-fix status
whatsapp-real-dns-fix rollback
```

После успешного `apply` переподключите Wi-Fi на телефоне и проверьте текст,
изображение, голосовой и видеозвонок. Перезагрузка роутера обычно не нужна.

## Требования

- OpenWrt с `dnsmasq`, UCI и `nftables`;
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
VERSION=v1.0.0 sh /tmp/install.sh
```

Хеши релизных файлов публикуются в `SHA256SUMS`.

## Как это устроено

```text
Телефон -> dnsmasq -> реальный DNS только для WhatsApp
                    -> настоящий IP -> podkop_subnets -> прокси

Остальные домены -> DNS-вход sing-box -> FakeIP -> обычная логика Podkop
```

Прямое добавление правил в `dhcp.@dnsmasq[0].server` ненадёжно: Podkop может
пересобрать этот UCI-список при перезапуске. Поэтому правила лежат в отдельном
`confdir`, подключённом к dnsmasq.

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
