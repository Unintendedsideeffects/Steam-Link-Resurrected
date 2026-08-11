#!/bin/sh

# Steam Link's minimal userspace sometimes fails to recreate /dev/hidrawN
# after a USB device resets, even though the kernel has rebound the device.
# This startup hook must finish: a long-running child is still waited for by
# the firmware's BusyBox startup runner and prevents later hooks from running.
for sysdev in /sys/class/hidraw/hidraw*; do
    [ -e "$sysdev" ] || continue
    name=${sysdev##*/}
    node=/dev/$name
    [ -e "$node" ] && continue

    dev=$(cat "$sysdev/dev" 2>/dev/null) || continue
    major=${dev%:*}
    minor=${dev#*:}
    mknod "$node" c "$major" "$minor" 2>/dev/null || true
    chmod 600 "$node" 2>/dev/null || true
done
exit 0
