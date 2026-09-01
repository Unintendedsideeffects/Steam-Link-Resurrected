#!/bin/sh
# Start Steam Link bundled VirtualHere USB Server for headless USB-over-Ethernet.
ENABLE=$(sed -n 's/^ENABLE_VIRTUALHERE=//p' /mnt/config/setup/setup.conf 2>/dev/null | head -n1 | tr -d '\r')
[ -n "$ENABLE" ] || ENABLE=1
if [ "$ENABLE" = 1 ]; then rm -f /mnt/config/setup/disable-virtualhere.txt; else : > /mnt/config/setup/disable-virtualhere.txt; fi
[ -f /mnt/config/setup/disable-virtualhere.txt ] && exit 0
LOG=/mnt/config/log/vhusbd-startup.log
VHLOG=/mnt/config/log/vhusbd.log
BIN=/home/steam/bin/vhusbdarmsl
PIDFILE=/var/run/vhusbdarm.pid
ROTATE_BYTES=10485760

mkdir -p /mnt/config/log /var/run
{
  echo "--- $(date) S99vhusbd starting ---"
  if [ ! -x "$BIN" ]; then
    echo "missing or non-executable $BIN"
    exit 0
  fi
  if pidof vhusbdarmsl >/dev/null 2>&1 || pidof vhusbdarm >/dev/null 2>&1; then
    echo "VirtualHere already running: $(pidof vhusbdarmsl 2>/dev/null) $(pidof vhusbdarm 2>/dev/null)"
    exit 0
  fi
  (
    sleep 8
    SIZE=$(stat -c %s "$VHLOG" 2>/dev/null || echo 0)
    case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
    if [ "$SIZE" -ge "$ROTATE_BYTES" ]; then
      mv -f "$VHLOG" "$VHLOG.1" 2>/dev/null || true
    fi
    "$BIN" -b >>"$VHLOG" 2>&1 &
    echo $! > "$PIDFILE"
    echo "started vhusbdarmsl pid $(cat "$PIDFILE")"
    while :; do
      sleep 300
      SIZE=$(stat -c %s "$VHLOG" 2>/dev/null || echo 0)
      case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
      if [ "$SIZE" -ge "$ROTATE_BYTES" ]; then
        cp "$VHLOG" "$VHLOG.1" 2>/dev/null || true
        : > "$VHLOG"
      fi
    done
  ) &
} >> "$LOG" 2>&1
exit 0
