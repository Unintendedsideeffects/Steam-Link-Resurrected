#!/bin/sh
set -eu
CONF=/mnt/config/setup/setup.conf
DISABLE=/mnt/config/setup/disable-setup-web.txt
CSRF=/var/run/steamlink-setup.csrf
get() { sed -n "s/^$1=//p" "$CONF" | head -n 1 | tr -d '\r'; }
html() { sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/"/\&quot;/g'; }
field() { printf '%s' "$BODY" | tr '&' '\n' | sed -n "s/^$1=//p" | busybox httpd -d 2>/dev/null || true; }
fail() { printf 'Status: %s\r\nWWW-Authenticate: Basic realm="Steam Link Setup"\r\nContent-Type: text/plain\r\n\r\n%s\n' "$1" "$2"; exit 0; }
WEB_SECRET=$(get WEB_SECRET); [ -n "$WEB_SECRET" ] || fail '503 Service Unavailable' 'Setup secret is not provisioned'
expected=$(printf 'admin:%s' "$WEB_SECRET" | base64)
[ "${HTTP_AUTHORIZATION-}" = "Basic $expected" ] || fail '401 Unauthorized' 'Authentication required'
CSRF_VALUE=$(cat "$CSRF" 2>/dev/null || true)
[ -n "$CSRF_VALUE" ] || fail '503 Service Unavailable' 'Setup protection is not initialized'
if [ "${REQUEST_METHOD-GET}" = POST ]; then
    length=${CONTENT_LENGTH-0}; case "$length" in ''|*[!0-9]*) fail '400 Bad Request' 'Invalid content length';; esac
    [ "$length" -le 8192 ] || fail '413 Payload Too Large' 'Request too large'
    BODY=$(dd bs=1 count="$length" 2>/dev/null)
    [ "$(field csrf)" = "$CSRF_VALUE" ] || fail '403 Forbidden' 'Invalid CSRF token'
    ACTION=$(field action); BUSID=$(field busid)
    case "$ACTION" in
    disable_web) : >"$DISABLE"; sh /mnt/config/setup/stop-web.sh 2>/dev/null || true;;
    save)
        NEW_HOST=$(field hostname); NEW_SSID=$(field wifi_ssid); NEW_PASS=$(field wifi_password)
        case "$NEW_HOST" in ''|*[!A-Za-z0-9_.-]*) fail '400 Bad Request' 'Invalid hostname';; esac
        n=$(printf '%s' "$NEW_SSID" | wc -c | tr -d ' '); [ "$n" -le 32 ] && [ "$n" -gt 0 ] || fail '400 Bad Request' 'Invalid SSID'
        case "$NEW_SSID$NEW_PASS" in *[![:print:]]*) fail '400 Bad Request' 'Invalid Wi-Fi value';; esac
        [ -n "$NEW_PASS" ] || NEW_PASS=$(get WIFI_PASSWORD)
        pass_n=$(printf '%s' "$NEW_PASS" | wc -c | tr -d ' '); [ "$pass_n" -eq 0 ] || [ "$pass_n" -ge 8 ] || fail '400 Bad Request' 'WPA Wi-Fi password must be at least 8 bytes'
        tmp="$CONF.$$"; {
            printf 'SETUP_SSID=%s\nSETUP_PASSWORD=%s\nWEB_SECRET=%s\nHOSTNAME=%s\nWIFI_SSID=%s\nWIFI_PASSWORD=%s\n' "$(get SETUP_SSID)" "$(get SETUP_PASSWORD)" "$(get WEB_SECRET)" "$NEW_HOST" "$NEW_SSID" "$NEW_PASS"
            printf 'ENABLE_SSH=%s\nENABLE_USBIP=%s\nENABLE_VIRTUALHERE=%s\nENABLE_MQTT=%s\n' "$(get ENABLE_SSH)" "$(get ENABLE_USBIP)" "$(get ENABLE_VIRTUALHERE)" "$(get ENABLE_MQTT)"
        } >"$tmp"; chmod 600 "$tmp"; mv "$tmp" "$CONF"
        if [ -f /mnt/config/steamlink-usbip.conf ]; then
            host_tmp=/mnt/config/steamlink-usbip.conf.$$;
            awk -v host="$NEW_HOST" 'BEGIN{found=0} /^STEAMLINK_HOSTNAME=/{print "STEAMLINK_HOSTNAME=" host; found=1; next} {print} END{if(!found) print "STEAMLINK_HOSTNAME=" host}' /mnt/config/steamlink-usbip.conf >"$host_tmp" && mv "$host_tmp" /mnt/config/steamlink-usbip.conf
        fi
        hostname "$NEW_HOST" 2>/dev/null || true
        sh /mnt/config/setup/apply-wifi.sh / "$NEW_SSID" "$NEW_PASS" >/mnt/config/log/setup-wifi.log 2>&1 || true
        # Leave the AP alive until the watcher observes a usable home/LAN
        # address. This prevents the save response from stranding a Wi-Fi
        # client before ConnMan has completed the connection.
        ;;
    usbip) case "$BUSID" in [0-9]-[0-9]|[0-9]-[0-9][0-9]|[0-9][0-9]-[0-9]|[0-9][0-9]-[0-9][0-9]) /mnt/config/usbip/bin/usbip-wrapper bind -b "$BUSID" >/mnt/config/log/setup-usbip.log 2>&1 || true;; esac;;
    unshare) case "$BUSID" in [0-9]-[0-9]|[0-9]-[0-9][0-9]|[0-9][0-9]-[0-9]|[0-9][0-9]-[0-9][0-9]) /mnt/config/usbip/bin/usbip-wrapper unbind -b "$BUSID" >/mnt/config/log/setup-usbip.log 2>&1 || true;; esac;;
    esac
fi
printf 'Content-Type: text/html\r\n\r\n'
token=$(cat "$CSRF" 2>/dev/null || true)
printf '<!doctype html><meta name="viewport" content="width=device-width"><title>Steam Link status</title><style>body{font:16px sans-serif;max-width:850px;margin:2em auto;padding:0 1em}section{border:1px solid #bbb;padding:1em;margin:1em 0}pre{white-space:pre-wrap;background:#eee;padding:1em}button{padding:.5em;margin:.2em}</style><h1>Steam Link status</h1>'
printf '<section><h2>Connection</h2><pre>'; { hostname; ifconfig -a 2>/dev/null; cat /proc/net/wireless 2>/dev/null; } | html; printf '</pre></section>'
printf '<section><h2>Features</h2><p>SSH: %s (disabling SSH risks losing access)<br>USB/IP: %s<br>VirtualHere: %s<br>Home Assistant MQTT: %s</p>' "$(get ENABLE_SSH)" "$(get ENABLE_USBIP)" "$(get ENABLE_VIRTUALHERE)" "$(get ENABLE_MQTT)"
printf '<form method="post"><input type="hidden" name="csrf" value="%s"><input type="hidden" name="action" value="save"><label>Hostname <input name="hostname" value="%s"></label><br><label>Wi-Fi SSID <input name="wifi_ssid" value="%s"></label><br><label>Wi-Fi password <input type="password" name="wifi_password"></label><br><button>Save settings</button></form>' "$token" "$(get HOSTNAME | html)" "$(get WIFI_SSID | html)"
printf '<form method="post"><input type="hidden" name="csrf" value="%s"><button name="action" value="disable_web">Disable setup web and AP now</button></form></section>' "$token"
printf '<section><h2>System</h2><pre>'; cat /proc/uptime /proc/loadavg; sed -n 's/^\(MemTotal\|MemFree\):.*/\1/p' /proc/meminfo; ps w 2>/dev/null | head -40 | html; printf '</pre></section>'
printf '<section><h2>USB devices</h2><pre>'; /mnt/config/usbip/bin/usbip-wrapper list -l 2>&1 | html; printf '</pre><form method="post"><input type="hidden" name="csrf" value="%s"><input name="busid" placeholder="USB/IP bus id"><button name="action" value="usbip">USB/IP share</button><button name="action" value="unshare">Unshare</button></form></section>' "$token"
