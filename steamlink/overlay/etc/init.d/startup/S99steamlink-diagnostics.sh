#!/bin/sh

# Persistent diagnostic snapshots for intermittent Steam Link failures.
# Opt-in via ENABLE_DIAGNOSTICS; the log must never be copied into Git.
# Steam Link BusyBox 1.24.1 implements timeout -t SECONDS.
ENABLE=$(sed -n 's/^ENABLE_DIAGNOSTICS=//p' /mnt/config/setup/setup.conf 2>/dev/null | head -n1 | tr -d '\r')
[ -n "$ENABLE" ] || ENABLE=0
if [ "$ENABLE" = 1 ]; then rm -f /mnt/config/setup/disable-diagnostics.txt; else : > /mnt/config/setup/disable-diagnostics.txt; fi
[ -f /mnt/config/setup/disable-diagnostics.txt ] && exit 0
LOG=/mnt/config/log/steamlink-diagnostics.log
PIDFILE=/var/run/steamlink-diagnostics.pid
ROTATE_BYTES=16777216
INTERVAL=15
USB_EVERY=4
SYNC_EVERY=4

mkdir -p /mnt/config/log /var/run

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PIDFILE"
fi

snapshot() {
    echo "===== diagnostic snapshot ====="
    echo "wall=$(date)"
    echo "boot_id=$BOOT_ID"
    echo "uptime=$(cat /proc/uptime)"
    echo "hostname=$(hostname)"
    echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
    echo "loadavg=$(cat /proc/loadavg 2>/dev/null || true)"
    echo "thermal="
    for NODE in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$NODE" ] || continue
        ZONE=${NODE%/temp}
        TYPE=$(cat "$ZONE/type" 2>/dev/null || echo unknown)
        echo "$(basename "$ZONE")_type=$TYPE"
        echo "$(basename "$ZONE")_temp=$(cat "$NODE" 2>/dev/null || true)"
    done
    echo "wireless_stats="
    cat /proc/net/wireless 2>/dev/null || true
    echo "watchdog="
    for NODE in /sys/class/watchdog/watchdog0/identity \
        /sys/class/watchdog/watchdog0/state \
        /sys/class/watchdog/watchdog0/status \
        /sys/class/watchdog/watchdog0/timeout \
        /sys/class/watchdog/watchdog0/pretimeout \
        /sys/class/watchdog/watchdog0/nowayout; do
        if [ -r "$NODE" ]; then
            echo "$(basename "$NODE")=$(cat "$NODE" 2>/dev/null || true)"
        fi
    done
    ls -l /dev/watchdog* 2>/dev/null || true
    echo "memory="
    sed -n -e '/^MemTotal:/p' -e '/^MemFree:/p' -e '/^Buffers:/p' \
        -e '/^Cached:/p' -e '/^SwapFree:/p' /proc/meminfo
    echo "mtd="
    cat /proc/mtd 2>/dev/null || true
    echo "partitions="
    cat /proc/partitions 2>/dev/null || true
    echo "storage_devices="
    for NODE in /sys/block/sda/device/vendor /sys/block/sda/device/model \
        /sys/block/sda/device/serial /sys/block/sda/size /sys/block/sda/ro; do
        if [ -r "$NODE" ]; then
            echo "$(basename "$NODE")=$(cat "$NODE" 2>/dev/null || true)"
        fi
    done
    echo "mounts="
    mount 2>/dev/null || true
    echo "network_devices="
    cat /proc/net/dev
    echo "interfaces="
    ifconfig -a 2>/dev/null || true
    echo "routes="
    route -n 2>/dev/null || true
    echo "listeners="
    netstat -lnt 2>/dev/null || true
    PROCESSES=$(ps w 2>/dev/null || true)
    echo "processes="
    printf '%s\n' "$PROCESSES"
    echo "firmware_processes="
    printf '%s\n' "$PROCESSES" | grep -E '[s]hell|[x]ow|P[E]_Single_CPU|[p]owermanager|[w]atchdog|[s]team' || true
    echo "interrupts="
    cat /proc/interrupts 2>/dev/null || true
    if [ $((SNAPSHOT_SEQ % USB_EVERY)) -eq 0 ]; then
        echo "usb_devices="
        timeout -t 3 /mnt/config/usbip/bin/usbip-wrapper list -l 2>&1 || true
    else
        echo "usb_devices=skipped snapshot_seq=$SNAPSHOT_SEQ"
    fi
    DMESG_TMP=/tmp/steamlink-diagnostics-dmesg.$$
    DMESG_NEW_TMP=/tmp/steamlink-diagnostics-dmesg-new.$$
    dmesg >"$DMESG_TMP" 2>/dev/null || true
    DMESG_LINES=$(wc -l <"$DMESG_TMP" 2>/dev/null || echo 0)
    case "$DMESG_LINES" in
        ''|*[!0-9]*) DMESG_LINES=0 ;;
    esac
    if [ "$DMESG_SEEN" -eq 0 ]; then
        echo "kernel_tail="
        tail -n 160 "$DMESG_TMP" 2>/dev/null || true
        : >"$DMESG_NEW_TMP"
        echo "kernel_new=none"
    else
        echo "kernel_new="
        if [ "$DMESG_LINES" -gt "$DMESG_SEEN" ]; then
            tail -n +$((DMESG_SEEN + 1)) "$DMESG_TMP" >"$DMESG_NEW_TMP" 2>/dev/null || true
            cat "$DMESG_NEW_TMP" 2>/dev/null || true
        else
            : >"$DMESG_NEW_TMP"
            echo "none"
        fi
    fi
    echo "kernel_markers="
    if [ "$DMESG_SEEN" -eq 0 ]; then
        grep -Ei 'panic|oops|bug:|watchdog|fatal|failed|error|reset|overflow|wlan|mlan|usbip|vhusbd|esphome' "$DMESG_TMP" 2>/dev/null | tail -n 80 || true
    else
        grep -Ei 'panic|oops|bug:|watchdog|fatal|failed|error|reset|overflow|wlan|mlan|usbip|vhusbd|esphome' "$DMESG_NEW_TMP" 2>/dev/null | tail -n 80 || true
    fi
    DMESG_SEEN=$DMESG_LINES
    if [ -r /proc/last_kmsg ]; then
        echo "last_kmsg_tail="
        tail -n 200 /proc/last_kmsg 2>/dev/null || true
    fi
    rm -f "$DMESG_TMP"
    rm -f "$DMESG_NEW_TMP"
}

(
    BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)
    SNAPSHOT_SEQ=0
    SYNC_SEQ=0
    DMESG_SEEN=0
    {
        echo "===== diagnostics start ====="
        echo "wall=$(date)"
        echo "boot_id=$BOOT_ID"
        echo "pid=$$"
    } >>"$LOG" 2>&1
    sync
    while true; do
        SIZE=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
        case "$SIZE" in
            ''|*[!0-9]*) SIZE=0 ;;
        esac
        if [ "$SIZE" -ge "$ROTATE_BYTES" ]; then
            mv -f "$LOG" "$LOG.1" 2>/dev/null || true
            echo "$(date): rotated diagnostics log at ${SIZE} bytes" >>"$LOG" 2>&1
            sync
        fi
        SNAPSHOT_SEQ=$((SNAPSHOT_SEQ + 1))
        snapshot >>"$LOG" 2>&1
        SYNC_SEQ=$((SYNC_SEQ + 1))
        if [ "$SYNC_SEQ" -ge "$SYNC_EVERY" ]; then
            sync
            SYNC_SEQ=0
        fi
        sleep "$INTERVAL"
    done
) >/dev/null 2>&1 &

echo $! >"$PIDFILE"
exit 0
