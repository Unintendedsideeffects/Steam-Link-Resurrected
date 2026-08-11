#!/bin/sh

# Keep the USB/IP server alive across Steam Link boot ordering and daemon
# failures. The firmware runs startup hooks before networking and USB settle
# reliably, so a one-shot start can silently leave port 3240 down.
(
    while :; do
        if ! netstat -lnt 2>/dev/null | grep -q ':3240 '; then
            /mnt/config/usbip/bin/usbip-start
        fi
        sleep 10
    done
) >/mnt/config/log/usbip-supervisor.log 2>&1 &
