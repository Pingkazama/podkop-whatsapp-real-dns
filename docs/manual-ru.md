# WhatsApp зависает за Podkop: ручное исправление FakeIP для начинающих

Эта инструкция предназначена для OpenWrt, где установлен Podkop с sing-box и
включён режим FakeIP. Она исправляет ситуацию, когда WhatsApp у клиентов
локальной сети:

- оставляет сообщения с иконкой часов;
- периодически теряет соединение;
- нестабильно загружает изображения;
- нестабильно устанавливает аудио- или видеозвонки.

Проблема не привязана к Wi-Fi, телефону или конкретной операционной системе.
Она может проявиться на любом проводном или беспроводном устройстве, которое
использует этот OpenWrt как DNS-сервер. Переключение Wi-Fi/мобильной сети — лишь
одно из заметных проявлений, а не условие возникновения проблемы.

Инструкция полностью ручная. Она не требует стороннего установщика и использует
нейтральные имена файлов, поэтому её можно применять на обычной установке
OpenWrt + Podkop.

> Перед началом прочитайте инструкцию целиком. Не выполняйте команды наугад и
> не продолжайте, если проверка маршрута реальных IP завершилась ошибкой.

## Коротко: что именно мы меняем

В обычной схеме запрос выглядит примерно так:

```text
Клиент локальной сети
  -> dnsmasq на OpenWrt
  -> DNS-вход sing-box
  -> FakeIP из диапазона 198.18.0.0/15
  -> правила Podkop
  -> прокси
```

После исправления схема для WhatsApp будет такой:

```text
Клиент локальной сети
  -> dnsmasq на OpenWrt
  -> отдельный реальный DNS только для доменов WhatsApp
  -> настоящий IP WhatsApp
  -> nftables-набор Podkop podkop_subnets
  -> тот же прокси, который использовался раньше
```

Для всех остальных доменов схема не меняется: они по-прежнему могут получать
FakeIP и обрабатываться обычной логикой Podkop.

Изменение затрагивает только четыре доменных суффикса:

```text
whatsapp.com
whatsapp.net
whatsapp.biz
wa.me
```

Суффикс означает сам домен и все его поддомены. Например, правило для
`whatsapp.net` также действует для `api.whatsapp.net` и
`mmx-ds.cdn.whatsapp.net`.

## Что означают используемые термины

### DNS

DNS превращает имя наподобие `api.whatsapp.net` в IP-адрес сервера. Клиентское
устройство обычно спрашивает DNS у роутера, а на OpenWrt этот запрос принимает
`dnsmasq`.

### FakeIP

FakeIP — это не настоящий адрес WhatsApp. sing-box выдаёт клиенту специальный
адрес из тестового диапазона `198.18.0.0/15`, затем перехватывает обращение к
этому адресу и связывает его с исходным доменным именем.

Для многих приложений это работает нормально. В рассматриваемой конфигурации
клиенты WhatsApp с такой схемой работали нестабильно.

### dnsmasq

`dnsmasq` — локальный DNS-сервис OpenWrt. Именно к нему обычно обращаются
устройства домашней сети независимо от способа подключения.

dnsmasq умеет отправлять разные домены разным DNS-серверам. Мы используем это,
чтобы только WhatsApp получал настоящие адреса.

### UCI

UCI — стандартная система конфигурации OpenWrt. Команда `uci` меняет файлы в
`/etc/config/`, а `uci commit` сохраняет изменения постоянно.

### confdir и extraconftext

OpenWrt сам управляет рабочим `confdir` dnsmasq. На проверенном роутере это
`/tmp/dnsmasq.d`; каталог находится в RAM и нормально создаётся заново после
перезагрузки. Исправление не меняет этот параметр.

Постоянные правила хранятся в стандартном UCI-параметре `extraconftext` внутри
`/etc/config/dhcp`. При каждом запуске dnsmasq штатный init-скрипт OpenWrt
разворачивает их в файл `extraconfig.conf` внутри своего рабочего `confdir`.
Поэтому отдельный постоянный каталог `/etc/config/dnsmasq.d` не нужен.

### podkop_subnets

`podkop_subnets` — nftables-набор с реальными IP-подсетями, которые Podkop
должен отправлять через выбранный прокси-маршрут.

Это критически важно: недостаточно просто получить настоящий IP WhatsApp. Нужно
ещё убедиться, что этот IP не пойдёт напрямую через провайдера.

## Почему нельзя просто добавить правила в dhcp.@dnsmasq[0].server

На первый взгляд хочется выполнить что-то такое:

```sh
uci add_list dhcp.@dnsmasq[0].server='/whatsapp.net/REAL_DNS_IP'
```

Такое правило действительно может заработать сразу. Но Podkop во время своего
цикла запуска и остановки работает с тем же UCI-параметром `server`:

1. сохраняет существующие DNS-серверы;
2. удаляет активный список `server`;
3. добавляет DNS-вход sing-box, обычно `127.0.0.42`;
4. при остановке восстанавливает сохранённые значения.

Поэтому доменное правило, напрямую добавленное в `server`, может пропасть из
активной конфигурации после:

- `podkop restart`;
- обновления Podkop;
- перезапуска управляемых компонентов Podkop;
- некоторых восстановительных действий watchdog.

`extraconftext` решает эту проблему: Podkop продолжает управлять своим списком
`server`, а штатный init-скрипт dnsmasq добавляет наши четыре правила отдельно
и восстанавливает runtime-файл после каждого рестарта.

## Что эта инструкция не меняет

Она не делает следующее:

- не отключает FakeIP глобально;
- не удаляет списки `Meta`, `Russia inside` или другие community lists;
- не переключает VPS или прокси-профиль;
- не меняет firewall;
- не редактирует сгенерированный JSON sing-box;
- не добавляет большой статический список IP Meta, AWS или CDN;
- не требует перезагрузки всего роутера.

## Требования

Перед началом должны выполняться все условия:

1. На роутере установлен и запущен Podkop.
2. Запущен sing-box.
3. Проверяемое устройство использует этот OpenWrt как DNS-сервер.
4. Есть SSH-доступ к OpenWrt под пользователем `root`.
5. В Podkop уже настроен рабочий прокси-маршрут.
6. Community list `Meta` или другой используемый список уже добавляет реальные
   адреса WhatsApp в `podkop_subnets`.

Команды ниже выполняются непосредственно в SSH-консоли OpenWrt.

## Автоматический вариант

В этом же каталоге лежит нейтральный скрипт
[`whatsapp-real-dns-fix.sh`](whatsapp-real-dns-fix.sh). Он выполняет описанную
ниже процедуру автоматически, но сохраняет те же проверки и формат файлов.

Скопируйте его на роутер:

```sh
scp whatsapp-real-dns-fix.sh root@OPENWRT_IP:/tmp/
```

Войдите на роутер и проверьте синтаксис:

```sh
chmod 700 /tmp/whatsapp-real-dns-fix.sh
sh -n /tmp/whatsapp-real-dns-fix.sh
```

Сначала выполните только безопасную проверку без изменений:

```sh
/tmp/whatsapp-real-dns-fix.sh check
```

Успешная проверка обязательно подтверждает не только реальный DNS и маршруты,
но и отдельный контрольный FakeIP-вход sing-box:

```text
preflight:ok
real_dns_answer:available
all_real_ipv4_routes:podkop
sing_box_fakeip_engine:active
```

Если проверка прошла, примените исправление:

```sh
/tmp/whatsapp-real-dns-fix.sh apply
```

Скрипт самостоятельно:

1. проверит OpenWrt, dnsmasq, Podkop, sing-box, контрольный FakeIP DNS и
   nftables;
2. выберет обычный DNS IPv4 из настроек Podkop;
3. несколько раз проверит меняющиеся реальные IPv4 WhatsApp в
   `podkop_subnets`;
4. создаст небольшой root-only бэкап только тех файлов, которые сам меняет;
5. запишет четыре правила в UCI `extraconftext` и создаст managed state;
6. перезапустит только dnsmasq;
7. проверит реальные DNS-ответы, маршрутизацию и сохранение общего FakeIP;
8. при ошибке отдельно укажет отсутствие DNS-ответа, оставшийся FakeIP,
   реальный IP вне `podkop_subnets` или остановившийся dnsmasq;
9. автоматически восстановит исходный DHCP-конфиг, если финальный тест не
   пройдёт, и сообщит об откате только после проверки dnsmasq.

Автоматический вариант намеренно не создаёт полный `sysupgrade`-архив на самом
роутере. Такой архив может включать крупные пользовательские файлы из `/root`
и заполнить небольшой OpenWrt overlay ещё до применения исправления.
Существующие архивы от старых запусков автоматически не удаляются: сначала
проверьте и при необходимости сохраните их вне роутера.

### Обновление ранней автоматической версии

Если уже установлена v1.0.0, v1.0.1 или v1.0.2, сначала откатывать либо удалять её
DNS-конфигурацию не нужно. Установщик актуального релиза проверяет SHA256 и
синтаксис во временном каталоге, затем атомарно заменяет только
`/usr/bin/whatsapp-real-dns-fix`. При сбое финальной замены старый исполняемый
файл остаётся на месте; DNS-конфигурацию установщик не трогает.

После обновления инструмента выполните:

```sh
whatsapp-real-dns-fix check
whatsapp-real-dns-fix apply
whatsapp-real-dns-fix status
```

Для выпущенных managed state v2/v3/v4 команда `check` выполняет безопасные проверки
резолвера, маршрутов и FakeIP и печатает:

```text
existing_config:upgrade_supported
existing_config:source_state_v2
upgrade:ready
```

Для v1.0.1 номер будет `v3`, для v1.0.2 — `v4`. Затем `apply` сначала сохраняет
DHCP state и старый файл правила в минимальный бэкап, переносит правила в
`extraconftext` и мигрирует конфигурацию в state v5. Старый управляемый
`/etc/config/dnsmasq.d` удаляется только после бэкапа. Штатный
`/tmp/dnsmasq.d` не изменяется.
Неизвестная версия state останавливается до записи файлов с ошибкой
`error:unsupported_managed_state_version`.

Проверка уже установленного исправления:

```sh
/tmp/whatsapp-real-dns-fix.sh status
```

Автоматический откат:

```sh
/tmp/whatsapp-real-dns-fix.sh rollback
```

После успешной проверки скрипт можно сохранить постоянно:

```sh
cp /tmp/whatsapp-real-dns-fix.sh /usr/bin/whatsapp-real-dns-fix
chmod 700 /usr/bin/whatsapp-real-dns-fix
```

Тогда команды будут короче:

```sh
whatsapp-real-dns-fix status
whatsapp-real-dns-fix rollback
```

Остальная часть README подробно объясняет каждое действие скрипта и содержит
полную ручную процедуру на случай, если автоматический вариант использовать не
хочется.

## Шаг 1. Проверяем исходное состояние

Проверяем, что dnsmasq, Podkop и sing-box запущены:

```sh
/etc/init.d/dnsmasq status
/etc/init.d/podkop status
pidof sing-box
```

Ожидаемый результат:

- `dnsmasq` сообщает, что сервис работает;
- `podkop` сообщает, что сервис работает;
- `pidof sing-box` выводит один или несколько числовых PID.

Проверяем, какой ответ сейчас получает клиентский DNS:

```sh
nslookup api.whatsapp.net 127.0.0.1
```

При проблемной FakeIP-схеме среди IPv4-ответов обычно будет адрес, начинающийся
с `198.18.` или `198.19.`.

Проверяем DNS-вход sing-box напрямую:

```sh
nslookup api.whatsapp.net 127.0.0.42
```

Если Podkop использует стандартную схему FakeIP, здесь также ожидается адрес
`198.18.x.x` или `198.19.x.x`.

Если `127.0.0.42` вообще не отвечает, не копируйте команды вслепую: конкретная
установка Podkop может использовать другую схему DNS.

Новая версия автоматического скрипта остановит уже `check` с ошибкой
`fakeip_control_dns_failed_*`, не меняя конфигурацию. Если FakeIP DNS точно
работает на другом локальном IPv4, передайте его одинаково в `check` и `apply`:

```sh
FAKE_DNS=127.0.0.54 /tmp/whatsapp-real-dns-fix.sh check
FAKE_DNS=127.0.0.54 /tmp/whatsapp-real-dns-fix.sh apply
```

После успешной установки выбранный адрес сохраняется в managed state и
используется командами `status` и последующими обновлениями. Не подставляйте
произвольный публичный DNS: здесь нужен именно DNS-вход sing-box, возвращающий
FakeIP.

## Шаг 2. Находим реальный DNS-сервер

Смотрим два DNS-параметра Podkop:

```sh
uci -q get podkop.settings.dns_server
uci -q get podkop.settings.bootstrap_dns_server
```

Нужен обычный IPv4-адрес вида `A.B.C.D`. Значение не должно содержать:

- `https://`;
- `tls://`;
- имя домена;
- номер порта;
- пробелы.

Следующий блок сначала берёт `dns_server`, а если это не обычный IPv4 — пробует
`bootstrap_dns_server`:

```sh
REAL_DNS="$(uci -q get podkop.settings.dns_server 2>/dev/null || true)"

if ! printf '%s\n' "$REAL_DNS" | awk -F. '
    NF != 4 { exit 1 }
    {
        for (i = 1; i <= 4; i++)
            if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1
    }
' >/dev/null 2>&1; then
    REAL_DNS="$(uci -q get podkop.settings.bootstrap_dns_server 2>/dev/null || true)"
fi

if printf '%s\n' "$REAL_DNS" | awk -F. '
    NF != 4 { exit 1 }
    {
        for (i = 1; i <= 4; i++)
            if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1
    }
' >/dev/null 2>&1; then
    echo "Найден подходящий DNS IPv4"
else
    echo "ОШИБКА: в настройках Podkop нет обычного DNS IPv4"
    unset REAL_DNS
fi
```

Если появилась ошибка, остановитесь. Сначала нужно выбрать доступный обычный
DNS IPv4. Не подставляйте случайный адрес без проверки маршрута на следующем
шаге.

Проверяем, что выбранный сервер действительно возвращает реальные адреса:

```sh
nslookup api.whatsapp.net "$REAL_DNS"
```

Успешный результат должен содержать хотя бы один обычный IPv4 и не должен
содержать IPv4 из `198.18.0.0/15`.

## Шаг 3. Проверяем, что реальные IP пойдут через Podkop

Получаем все текущие IPv4-ответы WhatsApp:

```sh
REAL_IPS="$(
    nslookup api.whatsapp.net "$REAL_DNS" 2>/dev/null |
    awk '
        /^Name:[[:space:]]/ { in_answer = 1; next }
        in_answer {
            for (i = 1; i <= NF; i++) {
                value = $i
                sub(/[#:].*$/, "", value)
                if (value ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print value
            }
        }
    ' | awk '!seen[$0]++'
)"

printf '%s\n' "$REAL_IPS"
```

Переменная не должна быть пустой. Теперь проверяем каждый адрес в nftables:

```sh
ROUTE_CHECK_FAILED=0

for IP in $REAL_IPS; do
    if nft get element inet PodkopTable podkop_subnets "{ $IP }" >/dev/null 2>&1; then
        echo "$IP -> через Podkop"
    else
        echo "$IP -> ОШИБКА: адрес отсутствует в podkop_subnets"
        ROUTE_CHECK_FAILED=1
    fi
done

if [ "$ROUTE_CHECK_FAILED" = "0" ]; then
    echo "Все реальные IPv4 WhatsApp входят в маршрут Podkop"
else
    echo "НЕ ПРОДОЛЖАТЬ: возможен прямой выход WhatsApp через провайдера"
fi
```

Продолжать можно только при сообщении:

```text
Все реальные IPv4 WhatsApp входят в маршрут Podkop
```

Если хотя бы одного адреса нет в наборе:

1. обновите community lists Podkop;
2. проверьте, что включён список `Meta`;
3. дождитесь успешного обновления списков;
4. повторите весь шаг.

Не исправляйте это копированием случайного большого списка старых IP.

## Шаг 4. Делаем резервную копию

Создаём каталог с текущей датой и временем:

```sh
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/whatsapp-real-dns-backup-$STAMP"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
```

Сохраняем конфигурацию DHCP/dnsmasq:

```sh
cp -p /etc/config/dhcp "$BACKUP_DIR/dhcp"
```

Если остался файл ранней версии исправления, сохраняем и его для совместимости:

```sh
if [ -f /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf ]; then
    cp -p /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf \
        "$BACKUP_DIR/fix-conf"
fi
```

DHCP-файла достаточно для отката актуальной версии; `fix-conf` нужен только при
миграции старой. Проверяем
результат:

```sh
ls -la "$BACKUP_DIR"
test -s "$BACKUP_DIR/dhcp" && echo "Минимальный бэкап создан"
```

Если нужен ещё и полный системный бэкап, не сохраняйте его на маленький overlay.
Запустите следующую команду на доверенном компьютере, заменив адрес роутера:

```sh
ssh root@OPENWRT_IP 'sysupgrade -b -' > openwrt-config-backup.tar.gz
```

> Архив `openwrt-config-backup.tar.gz` может содержать пароли, ключи и другие
> приватные настройки. Не публикуйте и не отправляйте его посторонним.

## Шаг 5. Проверяем поддержку extraconftext и синтаксис правил

Убеждаемся, что init-скрипт этой сборки OpenWrt поддерживает постоянный
UCI-параметр `extraconftext`:

```sh
grep -F 'config_get extraconftext "$cfg" extraconftext' \
    /etc/init.d/dnsmasq
```

Если строка не найдена, остановитесь: описанный способ для этой сборки не
подтверждён. Затем проверяем, что параметр ещё не занят другой настройкой:

```sh
CURRENT_EXTRACONF="$(
    uci -q get dhcp.@dnsmasq[0].extraconftext 2>/dev/null || true
)"
test -z "$CURRENT_EXTRACONF" || {
    echo "СТОП: extraconftext уже используется"
    return 1 2>/dev/null || exit 1
}
```

Переменная `REAL_DNS` должна всё ещё содержать проверенный адрес из шага 2.
Создаём только временный файл для проверки синтаксиса:

```sh
TEST_CONF=/tmp/whatsapp-real-dns-test.conf
cat > "$TEST_CONF" <<EOF
server=/whatsapp.com/$REAL_DNS
server=/whatsapp.net/$REAL_DNS
server=/whatsapp.biz/$REAL_DNS
server=/wa.me/$REAL_DNS
EOF

dnsmasq --test --conf-file="$TEST_CONF"
rm -f "$TEST_CONF"
```

Ожидается сообщение об успешной проверке. При ошибке не перезапускайте dnsmasq.

## Шаг 6. Сохраняем правила через UCI extraconftext

Записываем четыре правила одной UCI-строкой с литеральными разделителями `\n`.
Штатный init-скрипт dnsmasq превратит их в четыре строки при запуске:

```sh
EXTRACONF_TEXT="server=/whatsapp.com/$REAL_DNS\\nserver=/whatsapp.net/$REAL_DNS\\nserver=/whatsapp.biz/$REAL_DNS\\nserver=/wa.me/$REAL_DNS"
uci set dhcp.@dnsmasq[0].extraconftext="$EXTRACONF_TEXT"
```

Существующий `confdir`, включая штатный `/tmp/dnsmasq.d`, не меняем. Создаём
небольшой state-файл для понятного ручного отката:

```sh
touch /etc/config/whatsapp_real_dns
chmod 600 /etc/config/whatsapp_real_dns

uci set whatsapp_real_dns.settings='settings'
uci set whatsapp_real_dns.settings.enabled='1'
uci set whatsapp_real_dns.settings.version='5'
uci set whatsapp_real_dns.settings.mode='extraconftext'
uci set whatsapp_real_dns.settings.resolver="$REAL_DNS"
uci set whatsapp_real_dns.settings.extraconftext_added='1'
uci set whatsapp_real_dns.settings.backup_dir="$BACKUP_DIR"

uci commit whatsapp_real_dns
uci commit dhcp
```

Проверяем постоянное значение, не раскрывая и не преобразуя его оболочкой:

```sh
uci -q get dhcp.@dnsmasq[0].extraconftext
```

В выводе должны быть четыре правила, разделённые символами `\n`.

## Шаг 7. Перезапускаем только dnsmasq

Перезагрузка всего роутера не нужна:

```sh
/etc/init.d/dnsmasq restart
sleep 3
/etc/init.d/dnsmasq status
```

Если dnsmasq не запустился, сразу переходите к разделу «Аварийный откат из
бэкапа».

Проверяем, что OpenWrt создал runtime-файл в своём текущем `confdir`:

```sh
GENERATED_CONF="$(
    ls -1 /var/etc/dnsmasq.conf.* /tmp/etc/dnsmasq.conf.* 2>/dev/null |
        head -1
)"
RUNTIME_CONFDIR="$(
    awk -F= '$1 == "conf-dir" { print $2; exit }' "$GENERATED_CONF"
)"
RUNTIME_CONFDIR="${RUNTIME_CONFDIR%%,*}"
printf 'Runtime confdir: %s\n' "$RUNTIME_CONFDIR"
sed -n '1,20p' "$RUNTIME_CONFDIR/extraconfig.conf"
```

В `extraconfig.conf` должны быть ровно четыре строки `server=...`. Сам файл
временный; его постоянный источник — `/etc/config/dhcp`.

## Шаг 8. Проверяем DNS после изменения

Запрашиваем WhatsApp через обычный DNS роутера:

```sh
nslookup api.whatsapp.net 127.0.0.1
```

Теперь IPv4-ответ должен быть настоящим. Адресов `198.18.x.x` и `198.19.x.x`
здесь быть не должно.

При этом DNS-вход sing-box должен по-прежнему выдавать FakeIP:

```sh
nslookup api.whatsapp.net 127.0.0.42
```

Здесь, наоборот, ожидается `198.18.x.x` или `198.19.x.x`. Это подтверждает, что
мы не отключили FakeIP глобально, а сделали только точечное исключение в
dnsmasq.

Снова проверяем маршрут всех реальных IPv4, но теперь получаем их через обычный
DNS роутера:

```sh
ROUTER_IPS="$(
    nslookup api.whatsapp.net 127.0.0.1 2>/dev/null |
    awk '
        /^Name:[[:space:]]/ { in_answer = 1; next }
        in_answer {
            for (i = 1; i <= NF; i++) {
                value = $i
                sub(/[#:].*$/, "", value)
                if (value ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print value
            }
        }
    ' | awk '!seen[$0]++'
)"

CHECK_FAILED=0

for IP in $ROUTER_IPS; do
    case "$IP" in
        198.18.*|198.19.*)
            echo "$IP -> ОШИБКА: роутер всё ещё возвращает FakeIP"
            CHECK_FAILED=1
            ;;
        *)
            if nft get element inet PodkopTable podkop_subnets "{ $IP }" >/dev/null 2>&1; then
                echo "$IP -> реальный адрес, маршрут Podkop найден"
            else
                echo "$IP -> ОШИБКА: реальный адрес не входит в маршрут Podkop"
                CHECK_FAILED=1
            fi
            ;;
    esac
done

if [ -n "$ROUTER_IPS" ] && [ "$CHECK_FAILED" = "0" ]; then
    echo "DNS и маршрут WhatsApp настроены правильно"
else
    echo "Проверка не пройдена"
fi
```

Также проверяем обычный DNS и доступ в Интернет:

```sh
nslookup openwrt.org 127.0.0.1
wget -q -T 15 -O /dev/null \
    http://connectivitycheck.gstatic.com/generate_204 \
    && echo "HTTP работает"
```

## Шаг 9. Проверяем, что Podkop не сотрёт правило

На этом шаге прокси-маршрут кратковременно перезапустится. Активные соединения
могут оборваться на несколько секунд.

Перезапускаем Podkop:

```sh
/etc/init.d/podkop restart
```

На слабом роутере нужно подождать дольше:

```sh
sleep 12
```

Проверяем сервисы:

```sh
/etc/init.d/podkop status
/etc/init.d/dnsmasq status
pidof sing-box
```

Проверяем, что постоянное значение и заново созданный runtime-файл на месте:

```sh
uci -q get dhcp.@dnsmasq[0].extraconftext
test -s "$RUNTIME_CONFDIR/extraconfig.conf" \
    && echo "Runtime-файл правила восстановлен"
```

Повторяем главную DNS-проверку:

```sh
nslookup api.whatsapp.net 127.0.0.1
```

Если роутер снова возвращает настоящий IPv4, а не `198.18.x.x`/`198.19.x.x`,
правило пережило реальный рестарт Podkop.

## Шаг 10. Проверяем WhatsApp на клиентском устройстве

Устройство должно оставаться в локальной сети этого роутера и использовать его
как DNS-сервер. Оно может быть подключено по Wi-Fi или Ethernet. Во время теста
не переключайте устройство на другой канал связи или другой DNS.

Порядок проверки:

1. Убедитесь, что устройство продолжает использовать проверяемую локальную
   сеть и DNS роутера.
2. Полностью закройте WhatsApp и откройте снова.
3. Отправьте несколько текстовых сообщений подряд.
4. Подождите одну-две минуты и отправьте ещё одно сообщение.
5. Отправьте изображение.
6. Откройте полученное изображение.
7. Выполните аудиозвонок.
8. Выполните видеозвонок.
9. Не меняйте подключение 5–10 минут и повторите отправку сообщения.

Успехом считается стабильная работа без смены сети и без иконки часов у
отправляемых сообщений.

## Обычный ручной откат

Этот способ используется, если роутер доступен и dnsmasq запускается.

Сначала убеждаемся, что state относится к актуальному способу хранения:

```sh
test "$(uci -q get whatsapp_real_dns.settings.mode)" = "extraconftext" || {
    echo "СТОП: неизвестный режим; используйте бэкап"
    return 1 2>/dev/null || exit 1
}

REAL_DNS="$(uci -q get whatsapp_real_dns.settings.resolver)"
EXPECTED_EXTRACONF="server=/whatsapp.com/$REAL_DNS\\nserver=/whatsapp.net/$REAL_DNS\\nserver=/whatsapp.biz/$REAL_DNS\\nserver=/wa.me/$REAL_DNS"
CURRENT_EXTRACONF="$(
    uci -q get dhcp.@dnsmasq[0].extraconftext 2>/dev/null || true
)"
test "$CURRENT_EXTRACONF" = "$EXPECTED_EXTRACONF" || {
    echo "СТОП: extraconftext изменён после установки; используйте бэкап"
    return 1 2>/dev/null || exit 1
}
```

Удаляем только управляемый параметр `extraconftext`. `confdir` не трогаем:

```sh
uci -q delete dhcp.@dnsmasq[0].extraconftext
```

Сохраняем DHCP-конфигурацию и удаляем только наш state-файл:

```sh
uci commit dhcp
rm -f /etc/config/whatsapp_real_dns
```

Перезапускаем dnsmasq:

```sh
/etc/init.d/dnsmasq restart
sleep 3
/etc/init.d/dnsmasq status
```

После отката запрос через роутер снова может возвращать FakeIP:

```sh
nslookup api.whatsapp.net 127.0.0.1
```

## Аварийный откат из бэкапа

Если dnsmasq не запускается или UCI-конфигурация повреждена, восстанавливаем
файл DHCP из созданного бэкапа.

Сначала находим последний каталог:

```sh
ls -1dt /root/whatsapp-real-dns-backup-* | head -1
```

Записываем найденный путь:

```sh
BACKUP_DIR="$(ls -1dt /root/whatsapp-real-dns-backup-* | head -1)"
echo "$BACKUP_DIR"
```

Восстанавливаем DHCP-конфигурацию:

```sh
cp -p "$BACKUP_DIR/dhcp" /etc/config/dhcp
```

Удаляем managed state. Восстановленный DHCP-файл уже вернул прежнее значение
`extraconftext` и не меняет штатный `confdir`:

```sh
rm -f /etc/config/whatsapp_real_dns
```

Если бэкап создавался при миграции старой версии, восстанавливаем её прежний
файл правила. Другие файлы каталога не перемещаем и не перезаписываем:

```sh
if [ -f "$BACKUP_DIR/fix-conf" ]; then
    mkdir -p /etc/config/dnsmasq.d
    cp -p "$BACKUP_DIR/fix-conf" \
        /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
else
    rm -f /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
    rmdir /etc/config/dnsmasq.d 2>/dev/null || true
fi
```

Перезапускаем dnsmasq:

```sh
/etc/init.d/dnsmasq restart
sleep 3
/etc/init.d/dnsmasq status
```

Если полный конфигурационный архив был отдельно сохранён на доверенном
компьютере, его можно использовать по стандартной процедуре `sysupgrade -r`.
Для отката данного исправления обычно достаточно вернуть `/etc/config/dhcp` и
удалить managed state. Старый файл правила нужен только при обратной миграции.

## Типовые проблемы

### `apply` сообщает об ошибке postcheck

Скрипт печатает причину и безопасные счётчики перед откатом, не раскрывая сами
IP-адреса:

- `postcheck:dnsmasq_whatsapp_answer:no_ipv4_answer` — dnsmasq не вернул IPv4;
- `postcheck:dnsmasq_whatsapp_answer:fake_ipv4_answer` — dnsmasq продолжил
  возвращать FakeIP;
- `postcheck:dnsmasq_whatsapp_answer:real_ipv4_not_routed` — хотя бы один
  реальный IPv4 отсутствует в `podkop_subnets`; это терминальная проверка,
  поэтому скрипт не ждёт следующего DNS-ответа и сразу переходит к откату;
- `postcheck:dnsmasq_whatsapp_answer:dnsmasq_not_running` — dnsmasq остановился;
- `postcheck:dnsmasq_runtime_extraconf_detected` или суффикс `not_detected`
  показывает, создан ли штатным init-скриптом runtime-файл `extraconfig.conf`;
- `postcheck:sing_box_fakeip_engine_failed_no_ipv4_answer` — контрольный FakeIP
  DNS не ответил;
- `postcheck:sing_box_fakeip_engine_failed_not_fake` — контрольный DNS ответил
  обычным IPv4 вместо FakeIP.

`rollback:verified` и суффикс `_rolled_back` означают, что исходные файлы
восстановлены, dnsmasq перезапущен и его рабочее состояние проверено. Суффикс
`_rollback_failed_manual_recovery_required` означает, что автоматический откат
не подтверждён; не повторяйте `apply`, сохраните показанный путь `backup:` и
используйте раздел «Аварийный откат из бэкапа».

Строка `error:existing_dnsmasq_extraconftext_conflict` появляется до любых
изменений, если `extraconftext` уже занят другой настройкой. Скрипт не
перезаписывает чужую DNS-конфигурацию автоматически. Обычный
`option confdir '/tmp/dnsmasq.d'` конфликтом не является и не меняется.

Строка `error:dnsmasq_extraconftext_unsupported` означает, что init-скрипт этой
сборки OpenWrt не содержит проверенного механизма `extraconftext`; запись не
выполняется.

Строка `error:existing_dnsmasq_runtime_extraconf_conflict` означает, что при
пустом UCI-параметре в runtime-каталоге уже лежит непустой
`extraconfig.conf`. Скрипт не перезаписывает такой необъяснённый файл.

### После изменения роутер всё равно возвращает FakeIP

Проверьте постоянное UCI-значение:

```sh
uci -q get dhcp.@dnsmasq[0].extraconftext
```

Найдите реальный runtime-каталог в сгенерированной конфигурации dnsmasq:

```sh
grep -Hn '^conf-dir=' \
    /var/etc/dnsmasq.conf.* /tmp/etc/dnsmasq.conf.* 2>/dev/null
```

Для показанного в диагностике `/tmp/dnsmasq.d` проверьте созданный файл:

```sh
sed -n '1,20p' /tmp/dnsmasq.d/extraconfig.conf
```

После исправления перезапустите только dnsmasq и повторите `nslookup`.

### Настоящий IP отсутствует в podkop_subnets

Не оставляйте исправление в таком состоянии: часть WhatsApp-трафика может
пойти напрямую.

Проверьте обновление community lists и список `Meta`. После обновления повторите
проверку каждого IP через `nft get element`.

### dnsmasq не запускается

Проверьте синтаксис:

```sh
dnsmasq --test \
    --conf-file=/tmp/dnsmasq.d/extraconfig.conf
```

Затем посмотрите последние сообщения:

```sh
logread -e dnsmasq | tail -50
```

Если причина не очевидна, выполните аварийный откат из бэкапа.

### После технических проверок WhatsApp всё равно нестабилен

Убедитесь, что:

1. проверяемое устройство действительно использует DNS роутера;
2. Private DNS, DoH или локальный VPN на устройстве не обходит dnsmasq;
3. все IPv4 из ответа входят в `podkop_subnets`;
4. время на роутере корректное;
5. через тот же маршрут работают обычные HTTPS-сайты;
6. проблема воспроизводится без смены сети или DNS.

Не добавляйте сразу все домены Meta или тысячи IP. Сначала соберите DNS-трафик
конкретного проблемного устройства и выясните, какой дополнительный домен
действительно не покрыт четырьмя правилами.

## Итоговое состояние файлов

После успешной установки постоянным должен быть только managed state:

```text
/etc/config/whatsapp_real_dns
```

В `/etc/config/dhcp` должен присутствовать `option extraconftext` с четырьмя
правилами, разделёнными литеральными `\n`:

```text
server=/whatsapp.com/REAL_DNS_IP\nserver=/whatsapp.net/REAL_DNS_IP\nserver=/whatsapp.biz/REAL_DNS_IP\nserver=/wa.me/REAL_DNS_IP
```

После запуска dnsmasq OpenWrt создаёт временный `extraconfig.conf` в своём
runtime-`confdir`. На показанном роутере это
`/tmp/dnsmasq.d/extraconfig.conf`, и файл содержит четыре строки:

```text
server=/whatsapp.com/REAL_DNS_IP
server=/whatsapp.net/REAL_DNS_IP
server=/whatsapp.biz/REAL_DNS_IP
server=/wa.me/REAL_DNS_IP
```

В реальном файле вместо `REAL_DNS_IP` будет выбранный обычный DNS IPv4.
Существующее значение `confdir` остаётся таким, каким его настроил OpenWrt.

## Полезные ссылки

- Публичный проект и релизы:
  [Pingkazama/podkop-whatsapp-real-dns](https://github.com/Pingkazama/podkop-whatsapp-real-dns).
- Обсуждения похожего поведения WhatsApp в Podkop:
  [#378](https://github.com/itdoginfo/podkop/issues/378),
  [#390](https://github.com/itdoginfo/podkop/issues/390),
  [#374](https://github.com/itdoginfo/podkop/issues/374),
  [#287](https://github.com/itdoginfo/podkop/issues/287).
- Документация sing-box FakeIP:
  <https://sing-box.sagernet.org/configuration/dns/server/fakeip/>.
- Документация sing-box для route action `resolve`:
  <https://sing-box.sagernet.org/configuration/route/rule_action/>.

`resolve_real_ip_for_routing` и настоящее DNS-исключение — не одно и то же.
Route action может разрешить реальный адрес внутри обработки маршрута sing-box,
но клиентское устройство при этом всё ещё способно получить FakeIP от DNS.
Здесь меняется именно ответ, который dnsmasq возвращает клиенту для доменов
WhatsApp.
