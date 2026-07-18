# WhatsApp зависает за Podkop: ручное исправление FakeIP для начинающих

Эта инструкция предназначена для OpenWrt, где установлен Podkop с sing-box и
включён режим FakeIP. Она исправляет ситуацию, когда WhatsApp на телефоне:

- оставляет сообщения с иконкой часов;
- иногда отправляет их только после переключения Wi-Fi на мобильную сеть;
- нестабильно загружает изображения;
- нестабильно устанавливает аудио- или видеозвонки.

Инструкция полностью ручная. Она не требует стороннего установщика и использует
нейтральные имена файлов, поэтому её можно применять на обычной установке
OpenWrt + Podkop.

> Перед началом прочитайте инструкцию целиком. Не выполняйте команды наугад и
> не продолжайте, если проверка маршрута реальных IP завершилась ошибкой.

## Коротко: что именно мы меняем

В обычной схеме запрос выглядит примерно так:

```text
Телефон
  -> dnsmasq на OpenWrt
  -> DNS-вход sing-box
  -> FakeIP из диапазона 198.18.0.0/15
  -> правила Podkop
  -> прокси
```

После исправления схема для WhatsApp будет такой:

```text
Телефон
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

DNS превращает имя наподобие `api.whatsapp.net` в IP-адрес сервера. Телефон
обычно спрашивает DNS у роутера, а на OpenWrt этот запрос принимает `dnsmasq`.

### FakeIP

FakeIP — это не настоящий адрес WhatsApp. sing-box выдаёт клиенту специальный
адрес из тестового диапазона `198.18.0.0/15`, затем перехватывает обращение к
этому адресу и связывает его с исходным доменным именем.

Для многих приложений это работает нормально. В рассматриваемой конфигурации
мобильный WhatsApp с такой схемой работал нестабильно.

### dnsmasq

`dnsmasq` — локальный DNS-сервис OpenWrt. Именно к нему обычно обращаются
телефоны и компьютеры в домашней сети.

dnsmasq умеет отправлять разные домены разным DNS-серверам. Мы используем это,
чтобы только WhatsApp получал настоящие адреса.

### UCI

UCI — стандартная система конфигурации OpenWrt. Команда `uci` меняет файлы в
`/etc/config/`, а `uci commit` сохраняет изменения постоянно.

### confdir

`confdir` — дополнительный каталог с конфигурационными файлами dnsmasq. В этой
инструкции используется:

```text
/etc/config/dnsmasq.d
```

Сам файл правил будет называться:

```text
/etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
```

Каталог специально находится внутри `/etc/config`, чтобы попасть в обычный
OpenWrt `sysupgrade`-бэкап.

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

Отдельный `confdir` решает эту проблему: Podkop продолжает управлять своим
списком `server`, а наши четыре правила загружаются dnsmasq из независимого
файла.

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
3. Телефон использует этот OpenWrt как DNS-сервер.
4. Есть SSH-доступ к OpenWrt под пользователем `root`.
5. В Podkop уже настроен рабочий прокси-маршрут.
6. Community list `Meta` или другой используемый список уже добавляет реальные
   адреса WhatsApp в `podkop_subnets`.

Команды ниже выполняются непосредственно в SSH-консоли OpenWrt.

## Автоматический вариант

В этом же каталоге лежит нейтральный скрипт
[`whatsapp-real-dns-fix.sh`](../whatsapp-real-dns-fix.sh). Он выполняет описанную
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

Если проверка прошла, примените исправление:

```sh
/tmp/whatsapp-real-dns-fix.sh apply
```

Скрипт самостоятельно:

1. проверит OpenWrt, dnsmasq, Podkop, sing-box и nftables;
2. выберет обычный DNS IPv4 из настроек Podkop;
3. проверит все реальные IPv4 WhatsApp в `podkop_subnets`;
4. создаст root-only бэкап и полный `sysupgrade -b` архив;
5. создаст нейтральный conf-файл и UCI state;
6. перезапустит только dnsmasq;
7. проверит реальные DNS-ответы, маршрутизацию и сохранение общего FakeIP;
8. автоматически восстановит исходный DHCP-конфиг, если финальный тест не
   пройдёт.

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

Если дополнительный каталог уже существовал, сохраняем и его:

```sh
if [ -d /etc/config/dnsmasq.d ]; then
    cp -a /etc/config/dnsmasq.d "$BACKUP_DIR/dnsmasq.d"
fi
```

Создаём полный стандартный конфигурационный архив OpenWrt:

```sh
sysupgrade -b "$BACKUP_DIR/sysupgrade-config.tar.gz"
chmod 600 "$BACKUP_DIR/sysupgrade-config.tar.gz"
```

Проверяем результат:

```sh
ls -la "$BACKUP_DIR"
test -s "$BACKUP_DIR/sysupgrade-config.tar.gz" && echo "Бэкап создан"
```

> Архив `sysupgrade-config.tar.gz` может содержать пароли, ключи и другие
> приватные настройки. Не публикуйте и не отправляйте его посторонним.

## Шаг 5. Создаём отдельный конфигурационный файл dnsmasq

Создаём каталог:

```sh
mkdir -p /etc/config/dnsmasq.d
chmod 700 /etc/config/dnsmasq.d
```

Создаём файл с четырьмя правилами. Переменная `REAL_DNS` должна всё ещё
содержать проверенный адрес из шага 2:

```sh
cat > /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf <<EOF
server=/whatsapp.com/$REAL_DNS
server=/whatsapp.net/$REAL_DNS
server=/whatsapp.biz/$REAL_DNS
server=/wa.me/$REAL_DNS
EOF

chmod 600 /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
```

Просматриваем созданный файл:

```sh
sed -n '1,20p' /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
```

В нём должно быть ровно четыре строки `server=...` и выбранный DNS IPv4.

Проверяем синтаксис файла до перезапуска рабочего DNS:

```sh
dnsmasq --test \
    --conf-file=/etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
```

Ожидается сообщение о том, что проверка синтаксиса успешна. При ошибке не
перезапускайте dnsmasq — исправьте файл или выполните откат из соответствующего
раздела ниже.

## Шаг 6. Подключаем confdir через UCI

Сначала проверяем, не подключён ли каталог ранее:

```sh
uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null |
    tr ' ' '\n' |
    grep -Fx /etc/config/dnsmasq.d
```

Если команда вывела `/etc/config/dnsmasq.d`, повторно добавлять значение не
нужно. Запоминаем это в переменной:

```sh
if uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null |
    tr ' ' '\n' |
    grep -Fx /etc/config/dnsmasq.d >/dev/null 2>&1; then
    CONFDIR_ADDED=0
    echo "confdir уже существовал"
else
    uci add_list dhcp.@dnsmasq[0].confdir='/etc/config/dnsmasq.d'
    CONFDIR_ADDED=1
    echo "confdir добавлен"
fi
```

Создаём небольшой нейтральный state-файл. Он нужен только для понятного ручного
отката:

```sh
touch /etc/config/whatsapp_real_dns
chmod 600 /etc/config/whatsapp_real_dns

uci set whatsapp_real_dns.settings='settings'
uci set whatsapp_real_dns.settings.enabled='1'
uci set whatsapp_real_dns.settings.mode='confdir'
uci set whatsapp_real_dns.settings.resolver="$REAL_DNS"
uci set whatsapp_real_dns.settings.confdir_added="$CONFDIR_ADDED"
uci set whatsapp_real_dns.settings.backup_dir="$BACKUP_DIR"
```

Сохраняем изменения:

```sh
uci commit whatsapp_real_dns
uci commit dhcp
```

Проверяем, что UCI видит каталог:

```sh
uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null |
    tr ' ' '\n' |
    grep -Fx /etc/config/dnsmasq.d
```

## Шаг 7. Перезапускаем только dnsmasq

Перезагрузка всего роутера не нужна:

```sh
/etc/init.d/dnsmasq restart
sleep 3
/etc/init.d/dnsmasq status
```

Если dnsmasq не запустился, сразу переходите к разделу «Аварийный откат из
бэкапа».

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

Проверяем, что файл на месте и confdir всё ещё подключён:

```sh
test -s /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf \
    && echo "Файл правила на месте"

uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null |
    tr ' ' '\n' |
    grep -Fx /etc/config/dnsmasq.d \
    && echo "confdir подключён"
```

Повторяем главную DNS-проверку:

```sh
nslookup api.whatsapp.net 127.0.0.1
```

Если роутер снова возвращает настоящий IPv4, а не `198.18.x.x`/`198.19.x.x`,
правило пережило реальный рестарт Podkop.

## Шаг 10. Проверяем WhatsApp на телефоне

Телефон должен быть подключён к Wi-Fi этого роутера. Во время теста не
переключайтесь на мобильную сеть.

Порядок проверки:

1. Отключите мобильные данные или убедитесь, что телефон продолжает
   использовать Wi-Fi.
2. Полностью закройте WhatsApp и откройте снова.
3. Отправьте несколько текстовых сообщений подряд.
4. Подождите одну-две минуты и отправьте ещё одно сообщение.
5. Отправьте изображение.
6. Откройте полученное изображение.
7. Выполните аудиозвонок.
8. Выполните видеозвонок.
9. Оставьте Wi-Fi включённым на 5–10 минут и повторите отправку сообщения.

Успехом считается стабильная работа без переключения Wi-Fi/4G и без иконки
часов у отправляемых сообщений.

## Обычный ручной откат

Этот способ используется, если роутер доступен и dnsmasq запускается.

Смотрим, добавляла ли инструкция новый confdir:

```sh
CONFDIR_ADDED="$(
    uci -q get whatsapp_real_dns.settings.confdir_added 2>/dev/null || echo 0
)"
```

Удаляем только файл WhatsApp:

```sh
rm -f /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
```

Если каталог был добавлен именно этой инструкцией, удаляем UCI-значение:

```sh
if [ "$CONFDIR_ADDED" = "1" ]; then
    uci -q del_list \
        dhcp.@dnsmasq[0].confdir='/etc/config/dnsmasq.d' || true
fi
```

Пустой каталог можно удалить. Если внутри есть другие файлы, каталог не
трогаем:

```sh
rmdir /etc/config/dnsmasq.d 2>/dev/null || true
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

Удаляем созданный файл:

```sh
rm -f /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
rm -f /etc/config/whatsapp_real_dns
```

Если до изменения существовал каталог `dnsmasq.d`, восстанавливаем его:

```sh
if [ -d "$BACKUP_DIR/dnsmasq.d" ]; then
    if [ -d /etc/config/dnsmasq.d ]; then
        FAILED_DIR="$BACKUP_DIR/dnsmasq.d.failed-$(date +%H%M%S)"
        mv /etc/config/dnsmasq.d "$FAILED_DIR"
        echo "Неудачная версия сохранена в $FAILED_DIR"
    fi
    cp -a "$BACKUP_DIR/dnsmasq.d" /etc/config/dnsmasq.d
else
    rmdir /etc/config/dnsmasq.d 2>/dev/null || true
fi
```

Перезапускаем dnsmasq:

```sh
/etc/init.d/dnsmasq restart
sleep 3
/etc/init.d/dnsmasq status
```

Если требуется восстановить весь конфигурационный архив OpenWrt, используйте
стандартную процедуру `sysupgrade -r`, но обычно для этого исправления достаточно
вернуть `/etc/config/dhcp` и каталог `dnsmasq.d`.

## Типовые проблемы

### После изменения роутер всё равно возвращает FakeIP

Проверьте наличие файла:

```sh
ls -l /etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
```

Проверьте UCI confdir:

```sh
uci -q get dhcp.@dnsmasq[0].confdir
```

Проверьте сгенерированную конфигурацию dnsmasq:

```sh
grep -R '/etc/config/dnsmasq.d' /var/etc/dnsmasq.conf.* 2>/dev/null
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
    --conf-file=/etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
```

Затем посмотрите последние сообщения:

```sh
logread -e dnsmasq | tail -50
```

Если причина не очевидна, выполните аварийный откат из бэкапа.

### После технических проверок WhatsApp всё равно нестабилен

Убедитесь, что:

1. телефон действительно использует DNS роутера;
2. Private DNS/DoH на телефоне или в браузере не обходит dnsmasq;
3. все IPv4 из ответа входят в `podkop_subnets`;
4. время на роутере корректное;
5. через тот же маршрут работают обычные HTTPS-сайты;
6. проблема воспроизводится без переключения Wi-Fi/4G.

Не добавляйте сразу все домены Meta или тысячи IP. Сначала соберите DNS-трафик
конкретного телефона и выясните, какой дополнительный домен действительно не
покрыт четырьмя правилами.

## Итоговое состояние файлов

После успешной установки должны существовать:

```text
/etc/config/dnsmasq.d/90-whatsapp-real-dns.conf
/etc/config/whatsapp_real_dns
```

В `/etc/config/dhcp` должен присутствовать список `confdir`, содержащий:

```text
/etc/config/dnsmasq.d
```

Файл `90-whatsapp-real-dns.conf` должен содержать четыре строки:

```text
server=/whatsapp.com/REAL_DNS_IP
server=/whatsapp.net/REAL_DNS_IP
server=/whatsapp.biz/REAL_DNS_IP
server=/wa.me/REAL_DNS_IP
```

В реальном файле вместо `REAL_DNS_IP` будет выбранный обычный DNS IPv4.

## Полезные ссылки

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
но телефон при этом всё ещё способен получить FakeIP от DNS. Здесь меняется
именно ответ, который dnsmasq возвращает клиенту для доменов WhatsApp.
