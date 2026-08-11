#!/bin/sh

PIDFILE=/var/run/steamlink-ntp-sync.pid

mkdir -p /var/run

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$PIDFILE"
fi

sync_time() {
    for PEER in pool.ntp.org time.cloudflare.com; do
        if /bin/ntpd -q -n -p "$PEER" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

(
    sleep 10
    while true; do
        if sync_time; then
            sleep 3600
        else
            sleep 60
        fi
    done
) >/dev/null 2>&1 &

echo $! >"$PIDFILE"
exit 0
