#!/bin/sh

LOG=/tmp/duckypad_hid_agent.log
BIN=/mnt/config/bin/duckypad_hid_agent
CONF=/mnt/config/usb-proxy/duckypad-hid-agent.conf
PIDFILE=/tmp/duckypad_hid_agent.pid

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    kill -0 "$PID" 2>/dev/null && exit 0
    rm -f "$PIDFILE"
fi

[ -x "$BIN" ] || exit 0
[ -s "$CONF" ] || exit 0

(
    while true; do
        echo "$(date): starting duckypad_hid_agent ($BIN $CONF)" >>"$LOG"
        "$BIN" "$CONF" >>"$LOG" 2>&1
        echo "$(date): duckypad_hid_agent exited, restarting in 5s" >>"$LOG"
        sleep 5
    done
) &

echo $! >"$PIDFILE"
