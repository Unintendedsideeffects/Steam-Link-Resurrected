#!/bin/sh

# Keep the USB/IP server alive across Steam Link boot ordering and daemon
# failures. The firmware runs startup hooks before networking and USB settle
# reliably, so a one-shot start can silently leave port 3240 down.
ENABLE=$(sed -n 's/^ENABLE_USBIP=//p' /mnt/config/setup/setup.conf 2>/dev/null | head -n1 | tr -d '\r')
[ -n "$ENABLE" ] || ENABLE=1
if [ "$ENABLE" = 1 ]; then rm -f /mnt/config/setup/disable-usbip.txt; else : > /mnt/config/setup/disable-usbip.txt; fi
[ -f /mnt/config/setup/disable-usbip.txt ] && exit 0
(
    while :; do
        [ -f /mnt/config/setup/disable-usbip.txt ] && exit 0
        if ! netstat -lnt 2>/dev/null | grep -q ':3240 '; then
            /mnt/config/usbip/bin/usbip-start
        fi
        sleep 10
    done
) >/mnt/config/log/usbip-supervisor.log 2>&1 &
