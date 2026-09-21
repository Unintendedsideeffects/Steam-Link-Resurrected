#!/bin/sh

# Device-local guarded recovery watchdog.
#
# This service is inert unless the device-local marker below exists.  When
# enabled, it leaves the normal diagnostics service running, waits ten
# minutes for eth0 to obtain an address, and only then creates the official
# root-level USB factory-reset marker.  It deliberately does not reboot: the
# next physical power cycle performs the reset, leaving the diagnostic record
# available for collection first.

ENABLE=/mnt/config/system/enable_lan_factory_reset_watchdog.txt
LOG=/mnt/config/log/boot-watchdog.log
PIDFILE=/var/run/steamlink-boot-watchdog.pid
WAIT_SECONDS=600

[ -f "$ENABLE" ] || exit 0
mkdir -p /mnt/config/log /var/run

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
fi

(
    echo "===== boot watchdog start ====="
    echo "wall=$(date)"
    echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
    echo "wait_seconds=$WAIT_SECONDS"
    sync

    ELAPSED=0
    while [ "$ELAPSED" -lt "$WAIT_SECONDS" ]; do
        if ifconfig eth0 2>/dev/null | grep -q 'inet addr:'; then
            echo "lan=present elapsed=$ELAPSED"
            echo "No factory reset requested."
            sync
            exit 0
        fi
        sleep 15
        ELAPSED=$((ELAPSED + 15))
    done

    echo "lan=absent elapsed=$ELAPSED"
    echo "interfaces="
    ifconfig -a 2>/dev/null || true
    echo "routes="
    route -n 2>/dev/null || true
    echo "network_devices="
    cat /proc/net/dev 2>/dev/null || true
    echo "kernel_tail="
    dmesg 2>/dev/null | tail -n 240 || true

    RESET_MOUNT=/tmp/steamlink-factory-reset
    mkdir -p "$RESET_MOUNT"
    USB_DEV=
    for DEV in /dev/block/sda1 /dev/sda1 /dev/block/sdb1 /dev/sdb1; do
        if [ -b "$DEV" ]; then
            USB_DEV=$DEV
            break
        fi
    done

    if [ -n "$USB_DEV" ] && mount -t vfat "$USB_DEV" "$RESET_MOUNT" 2>>"$LOG"; then
        cp "$LOG" "$RESET_MOUNT/boot-watchdog-failure.log" 2>>"$LOG" || true
        cp /mnt/config/log/steamlink-diagnostics.log \
            "$RESET_MOUNT/steamlink-diagnostics-before-reset.log" 2>>"$LOG" || true
        mv "$RESET_MOUNT/steamlink/config/system/enable_lan_factory_reset_watchdog.txt" \
            "$RESET_MOUNT/steamlink/config/system/boot-watchdog-disabled-after-reset.txt" \
            2>>"$LOG" || true
        echo 1 >"$RESET_MOUNT/factory_reset.txt"
        sync
        echo "factory_reset_marker=created device=$USB_DEV"
        umount "$RESET_MOUNT" 2>>"$LOG" || true
    else
        echo "factory_reset_marker=failed device=${USB_DEV:-none}"
    fi
    sync
) >>"$LOG" 2>&1 &

echo $! >"$PIDFILE"
exit 0
