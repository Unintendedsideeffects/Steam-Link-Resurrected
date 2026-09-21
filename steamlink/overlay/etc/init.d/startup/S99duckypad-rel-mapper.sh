#!/bin/sh
#
# Relative-axis mapper for a duckyPad's scroll wheel: reads the evdev node and
# republishes over MQTT. Inert unless the binary is present, so it costs
# nothing on a device that has no duckyPad attached.
#
# MQTT settings come from the device-local usb-proxy config (the same file
# provision-key.sh writes), never from this file -- this repo is public.

LOG=/tmp/duckypad_rel_mapper.log
BIN=/mnt/config/bin/duckypad_rel_mapper
CONF=/mnt/config/usb-proxy/usb-proxy.conf
PIDFILE=/tmp/duckypad_rel_mapper.pid

[ -x "$BIN" ] || exit 0
[ -s "$CONF" ] || exit 0

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    kill -0 "$PID" 2>/dev/null && exit 0
    rm -f "$PIDFILE"
fi

get() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n1 | tr -d '\r'; }

MQTT_HOST=$(get MQTT_HOST)
MQTT_PORT=$(get MQTT_PORT); [ -n "$MQTT_PORT" ] || MQTT_PORT=1883
MQTT_USER=$(get MQTT_USER)
MQTT_PASSWORD=$(get MQTT_PASSWORD)
REL_EVENT=$(get REL_EVENT_DEVICE); [ -n "$REL_EVENT" ] || REL_EVENT=/dev/input/event1
REL_TOPIC=$(get REL_TOPIC); [ -n "$REL_TOPIC" ] || REL_TOPIC=usb-proxy/event

[ -n "$MQTT_HOST" ] && [ -n "$MQTT_USER" ] && [ -n "$MQTT_PASSWORD" ] || {
    echo "$(date): usb-proxy.conf has no MQTT credentials; not starting" >>"$LOG"
    exit 0
}
[ -e "$REL_EVENT" ] || { echo "$(date): $REL_EVENT absent; not starting" >>"$LOG"; exit 0; }

"$BIN" "$REL_EVENT" "$MQTT_HOST" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASSWORD" \
    "$REL_TOPIC" >>"$LOG" 2>&1 &
echo $! >"$PIDFILE"
