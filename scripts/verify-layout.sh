#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

required='steamlink/config/system/enable_ssh.txt
steamlink/config/system/suspend_timeout_idle.txt
steamlink/config/system/suspend_timeout_interactive.txt
steamlink/overlay/etc/init.d/startup/S01steamlink-ntp-sync.sh
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

if find steamlink -type f | grep -Eiq 'python|duckypad'; then
    echo "out-of-scope Python or DuckyPad file found" >&2
    exit 1
fi

for file in steamlink/overlay/etc/init.d/startup/*.sh scripts/*.sh; do
    sh -n "$file"
done

echo "layout OK"
