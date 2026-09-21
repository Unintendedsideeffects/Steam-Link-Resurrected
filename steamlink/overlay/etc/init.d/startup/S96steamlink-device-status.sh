#!/bin/sh
PIDFILE=/var/run/steamlink-device-status.pid
BIN=/mnt/config/bin/steamlink-device-status
LOG=/mnt/config/log/steamlink-device-status.log
[ -x "$BIN" ] || exit 0
[ -s /mnt/config/usb-proxy/usb-proxy.conf ] || exit 0
[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null && exit 0
mkdir -p /mnt/config/log /var/run
(
    cleanup() { rm -f "$PIDFILE"; }
    trap cleanup EXIT
    trap 'exit 143' 2 15
    while [ -s /mnt/config/usb-proxy/usb-proxy.conf ]; do
        echo "$(date): starting native device-status reporter" >>"$LOG"
        "$BIN" >>"$LOG" 2>&1
        rc=$?
        echo "$(date): reporter exited rc=$rc; retrying in 5s" >>"$LOG"
        sleep 5
    done
) >>"$LOG" 2>&1 &
echo $! >"$PIDFILE"
