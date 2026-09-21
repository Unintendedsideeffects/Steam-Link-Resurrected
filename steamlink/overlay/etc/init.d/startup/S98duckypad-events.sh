#!/bin/sh
#
# Launcher for duckypad_event_bridge. Inert unless both the script and its
# device-local config are present, so it costs nothing on a device that does
# not run this add-on.

LOG=/tmp/duckypad_event_bridge.log
PY=/mnt/config/bin/duckypad_event_bridge.py
CONF=/mnt/config/duckypad/duckypad_event_bridge.conf

[ -f "$PY" ] || exit 0
[ -s "$CONF" ] || exit 0

if [ -x /usr/bin/python3 ]; then
  /usr/bin/python3 "$PY" "$CONF" >> "$LOG" 2>&1 &
elif [ -x /usr/bin/python ]; then
  /usr/bin/python "$PY" "$CONF" >> "$LOG" 2>&1 &
else
  echo "No python interpreter found for duckypad_event_bridge" >> "$LOG"
fi
