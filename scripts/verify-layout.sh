#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

required='steamlink/config/system/enable_ssh.txt
steamlink/config/system/suspend_timeout_idle.txt
steamlink/config/system/suspend_timeout_interactive.txt
steamlink/overlay/etc/init.d/startup/S01steamlink-ntp-sync.sh
steamlink/overlay/etc/init.d/startup/S04steamlink-setup.sh
steamlink/overlay/etc/init.d/startup/S02hostname
steamlink/overlay/etc/init.d/startup/S97hidraw-nodes.sh
steamlink/overlay/etc/init.d/startup/S97usbip.sh
steamlink/overlay/etc/init.d/startup/S98steamlink-ble-proxy.sh
steamlink/overlay/etc/init.d/startup/S99vhusbd.sh
steamlink/overlay/etc/init.d/startup/S99steamlink-diagnostics.sh
steamlink/overlay/mnt/config/usbip/bin/usbipd
steamlink/overlay/mnt/config/ble-proxy/esphome-linux
steamlink/overlay/mnt/config/ble-proxy/ble-proxy.conf.example
steamlink/overlay/mnt/config/steamlink-ota.conf.example'

printf '%s\n' "$required" | while IFS= read -r file; do
    [ -e "$file" ] || { echo "missing: $file" >&2; exit 1; }
done

[ -f steamlink/overlay/mnt/config/setup/www/index.html ] || { echo "missing setup web index" >&2; exit 1; }
[ -f steamlink/overlay/mnt/config/setup/www/cgi-bin/setup.cgi ] || { echo "missing setup CGI" >&2; exit 1; }
[ -f steamlink/overlay/mnt/config/setup/apply-wifi.sh ] || { echo "missing Wi-Fi helper" >&2; exit 1; }
[ -f steamlink/overlay/mnt/config/setup/stop-web.sh ] || { echo "missing web stop helper" >&2; exit 1; }

if find steamlink -type f | grep -Eiq 'python|duckypad'; then
    echo "out-of-scope Python or DuckyPad file found" >&2
    exit 1
fi

for file in steamlink/overlay/etc/init.d/startup/*.sh scripts/*.sh; do
    sh -n "$file"
done
sh -n scripts/test-provision-key.sh
sh -n steamlink/overlay/mnt/config/setup/apply-wifi.sh
sh -n steamlink/overlay/mnt/config/setup/stop-web.sh
sh -n steamlink/overlay/mnt/config/setup/www/cgi-bin/setup.cgi

echo "layout OK"
