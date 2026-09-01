#!/bin/sh

LOG=/mnt/config/log/steamlink-ble-proxy.log
BIN=/mnt/config/ble-proxy/esphome-linux
PIDFILE=/var/run/steamlink-ble-proxy.pid
MAINTENANCE_PIDFILE=/var/run/steamlink-ble-proxy-maintenance.pid
BACKUP_CLEANUP_PIDFILE=/var/run/steamlink-ble-proxy-backup-cleanup.pid
BACKUP=/mnt/config/ble-proxy/esphome-linux.before-project-metadata-fix-20260722
ROTATE_BYTES=10485760
CONF=/mnt/config/ble-proxy/ble-proxy.conf
EXAMPLE=/mnt/config/ble-proxy/ble-proxy.conf.example

mkdir -p /mnt/config/log /var/run

load_proxy_env() {
    conf=$CONF
    [ -r "$conf" ] || conf=$EXAMPLE
    for name in LOG_LEVEL BLE_PROXY_VERBOSE ESPHOME_API_VERBOSE; do
        value=
        [ -r "$conf" ] && value=$(sed -n "s/^$name=//p" "$conf" | head -n 1 | tr -d '\r')
        if [ -n "$value" ]; then
            export "$name=$value"
        else
            unset "$name"
        fi
    done
}

proxy_is_healthy() {
    PIDS=$(pidof esphome-linux 2>/dev/null || true)
    for PID in $PIDS; do
        if kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

log_rotation_worker() {
    while true; do
        sleep 300

        # The proxy keeps the log file open, so rotate with copy-truncate
        # instead of rename; this preserves the writer's file descriptor.
        if [ -f "$LOG" ]; then
            SIZE=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
            case "$SIZE" in
                ''|*[!0-9]*) SIZE=0 ;;
            esac
            if [ "$SIZE" -ge "$ROTATE_BYTES" ]; then
                cp "$LOG" "$LOG.1" 2>/dev/null || true
                : > "$LOG"
                echo "$(date): rotated proxy log at ${SIZE} bytes" >>"$LOG"
            fi
        fi

    done
}

backup_cleanup_worker() {
    # Use sleep rather than filesystem timestamps because Steam Link clocks
    # are not guaranteed to be synchronized. If the proxy is unhealthy at
    # the deadline, retain the backup and retry hourly.
    sleep 86400
    while [ -f "$BACKUP" ]; do
        if proxy_is_healthy; then
            echo "$(date): proxy healthy after 24h; removing old binary backup" >>"$LOG"
            rm -f "$BACKUP"
            exit 0
        fi
        sleep 3600
    done
}

if [ -f "$MAINTENANCE_PIDFILE" ]; then
    MAINTENANCE_PID=$(cat "$MAINTENANCE_PIDFILE")
    if ! kill -0 "$MAINTENANCE_PID" 2>/dev/null; then
        rm -f "$MAINTENANCE_PIDFILE"
    fi
fi

if [ ! -f "$MAINTENANCE_PIDFILE" ]; then
    log_rotation_worker >>"$LOG" 2>&1 &
    echo $! >"$MAINTENANCE_PIDFILE"
fi

if [ -f "$BACKUP_CLEANUP_PIDFILE" ]; then
    BACKUP_CLEANUP_PID=$(cat "$BACKUP_CLEANUP_PIDFILE")
    if ! kill -0 "$BACKUP_CLEANUP_PID" 2>/dev/null; then
        rm -f "$BACKUP_CLEANUP_PIDFILE"
    fi
fi

if [ -f "$BACKUP" ] && [ ! -f "$BACKUP_CLEANUP_PIDFILE" ]; then
    backup_cleanup_worker >>"$LOG" 2>&1 &
    echo $! >"$BACKUP_CLEANUP_PIDFILE"
fi

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PIDFILE"
fi

[ -x "$BIN" ] || exit 0

(
    sleep 3
    while true; do
        # A direct HCI scanner can survive an unclean proxy exit. Reset the
        # adapter before each launch so the next scan-parameter command is not
        # rejected as "Command Disallowed" by the controller.
        hciconfig hci0 down >/dev/null 2>&1 || true
        sleep 1
        hciconfig hci0 up >/dev/null 2>&1 || true
        echo "$(date): starting Steam Link BLE proxy" >>"$LOG"
        load_proxy_env
        "$BIN" >>"$LOG" 2>&1
        RC=$?
        echo "$(date): BLE proxy exited rc=$RC; restarting in 5s" >>"$LOG"
        sleep 5
    done
) >/dev/null 2>&1 &

echo $! >"$PIDFILE"
exit 0
