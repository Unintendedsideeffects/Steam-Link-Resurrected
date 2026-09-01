#!/bin/sh
PIDFILE=/var/run/steamlink-setup-web.pid
if [ -r "$PIDFILE" ]; then
    pid=$(tr -d '\r' <"$PIDFILE")
    case "$pid" in ''|*[!0-9]*) ;; *) kill "$pid" 2>/dev/null || true;; esac
    rm -f "$PIDFILE"
fi
connmanctl tether wifi off >/dev/null 2>&1 || true
ifconfig uap0 0.0.0.0 down >/dev/null 2>&1 || true
