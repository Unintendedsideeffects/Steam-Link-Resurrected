#!/bin/sh
#
# Launcher for steamlink_usb_proxy. Inert unless both the script and its
# device-local config are present, so it costs nothing on a device that does
# not run this add-on.

LOG=/tmp/steamlink_usb_proxy.log
PY=/mnt/config/bin/steamlink_usb_proxy.py
CONF=/mnt/config/usb-proxy/usb-proxy.conf

[ -f "$PY" ] || exit 0
[ -s "$CONF" ] || exit 0

if [ -x /usr/bin/python3 ]; then
  /usr/bin/python3 "$PY" "$CONF" >> "$LOG" 2>&1 &
elif [ -x /usr/bin/python ]; then
  /usr/bin/python "$PY" "$CONF" >> "$LOG" 2>&1 &
else
  echo "No python interpreter found for steamlink_usb_proxy" >> "$LOG"
fi
