#!/bin/sh
set -eu

# First-boot setup AP and authenticated status web. Restore the persisted
# ConnMan home profile, then keep the AP up until a usable LAN address appears.
CONF=/mnt/config/setup/setup.conf
DISABLE=/mnt/config/setup/disable-setup-web.txt
PIDFILE=/var/run/steamlink-setup-web.pid
WWW=/mnt/config/setup/www
CSRF=/var/run/steamlink-setup.csrf
get() { sed -n "s/^$1=//p" "$CONF" | head -n 1 | tr -d '\r'; }
stop_web() { sh /mnt/config/setup/stop-web.sh; }
home_network_ready() {
    for path in /sys/class/net/*; do
        iface=${path##*/}
        case "$iface" in lo|uap0) continue;; esac
        addr=$(ifconfig "$iface" 2>/dev/null | sed -n -e 's/.*inet addr:\([^ ]*\).*/\1/p' -e 's/^[[:space:]]*inet[[:space:]]\+\([^ /]*\).*/\1/p' | head -n 1)
        [ -n "$addr" ] || continue
        case "$addr" in 127.*|169.254.*|192.168.42.1) continue;; esac
        return 0
    done
    return 1
}
[ -f "$DISABLE" ] && { stop_web; exit 0; }
[ -r "$CONF" ] || exit 0
SETUP_SSID=$(get SETUP_SSID); SETUP_PASSWORD=$(get SETUP_PASSWORD)
[ -n "$SETUP_SSID" ] && [ -n "$SETUP_PASSWORD" ] || exit 0
mkdir -p /mnt/config/log /var/run
chmod 755 "$WWW"/cgi-bin/*.cgi 2>/dev/null || true
if [ -f /mnt/config/setup/steamlinkhome.config ]; then
    mkdir -p /var/lib/connman
    cp /mnt/config/setup/steamlinkhome.config /var/lib/connman/steamlinkhome.config || true
    chmod 600 /var/lib/connman/steamlinkhome.config 2>/dev/null || true
fi
if home_network_ready; then stop_web; exit 0; fi
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then exit 0; fi
ifconfig uap0 192.168.42.1 netmask 255.255.255.0 up 2>/dev/null || true
connmanctl tether wifi on "$SETUP_SSID" "$SETUP_PASSWORD" >/mnt/config/log/setup-wifi.log 2>&1 || true
umask 077
if [ ! -s "$CSRF" ]; then od -An -N16 -tx1 /dev/urandom | tr -d ' \n' >"$CSRF"; fi
chmod 600 "$CSRF" 2>/dev/null || true
httpd -p 192.168.42.1:80 -h "$WWW" -f >/mnt/config/log/setup-httpd.log 2>&1 &
echo $! >"$PIDFILE"
(
    while [ ! -f "$DISABLE" ]; do
        if home_network_ready; then stop_web; exit 0; fi
        sleep 10
    done
    stop_web
) >/dev/null 2>&1 &
if [ "$(get ENABLE_USBIP)" = 1 ]; then rm -f /mnt/config/setup/disable-usbip.txt; else : > /mnt/config/setup/disable-usbip.txt; fi
if [ "$(get ENABLE_VIRTUALHERE)" = 1 ]; then rm -f /mnt/config/setup/disable-virtualhere.txt; else : > /mnt/config/setup/disable-virtualhere.txt; fi
exit 0
