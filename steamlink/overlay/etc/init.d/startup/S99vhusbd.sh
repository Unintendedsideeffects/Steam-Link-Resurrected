#!/bin/sh
# Start Steam Link bundled VirtualHere USB Server for headless USB-over-Ethernet.
ENABLE=$(sed -n 's/^ENABLE_VIRTUALHERE=//p' /mnt/config/setup/setup.conf 2>/dev/null | head -n1 | tr -d '\r')
[ -n "$ENABLE" ] || ENABLE=1
if [ "$ENABLE" = 1 ]; then rm -f /mnt/config/setup/disable-virtualhere.txt; else : > /mnt/config/setup/disable-virtualhere.txt; fi
[ -f /mnt/config/setup/disable-virtualhere.txt ] && exit 0
LOG=/mnt/config/log/vhusbd-startup.log
BIN=/home/steam/bin/vhusbdarmsl
PIDFILE=/var/run/vhusbdarm.pid

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
  sleep 8
  "$BIN" -b >>/mnt/config/log/vhusbd.log 2>&1 &
  echo $! > "$PIDFILE"
  echo "started vhusbdarmsl pid $(cat "$PIDFILE")"
} >> "$LOG" 2>&1
exit 0
