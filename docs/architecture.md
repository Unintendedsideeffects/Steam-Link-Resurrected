# Architecture & System Design

This document details how the `steamlink-usbip-bootstrap` distribution runs on the Valve Steam Link hardware and firmware.

---

## Hardware & Environment Overview

- **CPU Architecture**: ARMv7 (`armv7l`), 32-bit little-endian.
- **Root Shell**: `/bin/sh` or `/bin/ash` (BusyBox).
- **Core C Library**: GNU C Library (glibc) 2.19.
- **Python Runtime**: **None**. The stock firmware ships no Python interpreter (`python`, `python3`). Scripts relying on python fail immediately.

---

## Filesystem Structure and Persistence

The Steam Link root filesystem layout dictates how files persist across reboots:

1. **Root Filesystem (`/`)**:
   - Stored on read-only yaffs2 NAND flash.
   - Any writes directly to `/` fail with read-only filesystem errors.
   - The directory `/root` lives on this read-only filesystem and cannot be modified.

2. **Writable Overlay Mounts (`unionfs`)**:
   - The system mounts writable layers using `unionfs` for mutable system paths:
     - `/etc`
     - `/var`
     - `/usr/local`
     - `/home/steam`
   - The underlying writable backing storage for these unionfs mounts is `/mnt/config/overlay/<dir>` on flash memory.
   - As a result, writing files to `/etc/init.d/startup/` or `/home/steam/.ssh/` persists automatically across reboots.

3. **Persistent Flash Partition (`/mnt/config`)**:
   - Dedicated writable flash storage.
   - Houses configuration files, logs, binaries, and overlays:
     - `/mnt/config/system/` (system control markers and timeouts)
     - `/mnt/config/setup/` (provisioning web server, credentials, setup.conf)
     - `/mnt/config/ssh/` (SSH keys directory)
     - `/mnt/config/ble-proxy/` (ESPHome BLE proxy binary and configuration)
     - `/mnt/config/usbip/` (USB/IP server daemon, helper binaries, modules)
     - `/mnt/config/usb-proxy/` (USB proxy / status reporter configuration)
     - `/mnt/config/log/` (persistent service log directory)

4. **Removable Boot Key (`/dev/sda1` / `/dev/sdb1` / `/dev/block/*`)**:
   - Formatted as FAT32 (`vfat`) with volume label `STEAMLINK`.
   - Contains the `steamlink/` staging tree.
   - On boot, the stock firmware script `/etc/init.d/startup/S01config` looks for a connected USB storage device containing a `steamlink/` directory and copies `steamlink/config` to `/mnt/config` and merges `steamlink/overlay` into `/mnt/config/overlay`.

> [!WARNING]
> Because FAT32 does not support Unix file permissions or symlinks:
> - `chmod 600` or `chmod 700` executed against files on the USB key directly has no effect. Anyone with physical access to the USB key can read `setup.conf`, `steamlink-ota.conf`, and `authorized_keys`.
> - All symlinks in `steamlink/` must be dereferenced (`cp -rL`) when copying files onto the FAT32 filesystem.

---

## Boot Lifecycle & Startup Hook Execution

The Steam Link startup process is managed by `/etc/init.d/startup.sh`:

1. **Startup Execution Loop**:
   `/etc/init.d/startup.sh` discovers and launches services using:
   ```sh
   for script in $STARTUPDIR/S*; do
       [ -x "$script" ] && "$script"
   done
   ```
   where `$STARTUPDIR` evaluates to `/etc/init.d/startup`.
   
   **Critical Rule**: Any executable file starting with `S` in `/etc/init.d/startup/` is executed sequentially. Do not store backups in this directory (e.g., `S97usbip.sh.bak` or `S97usbip.sh.pre-fix`), as they will also be launched on boot as duplicate concurrent processes.

2. **First Boot vs. Subsequent Boots**:
   - On the **very first boot** with a newly provisioned USB key, the stock `/etc/init.d/startup/S01config` script copies the USB overlay onto flash. However, `startup.sh`'s initial file glob had already evaluated before the copy took place.
   - To ensure new services start immediately without requiring a second reboot, the overlay provides [`steamlink/overlay/etc/init.d/startup/S99steam`](../steamlink/overlay/etc/init.d/startup/S99steam).
   - [`S99steam`](../steamlink/overlay/etc/init.d/startup/S99steam) acts as a late anchor. If the marker file `/mnt/config/system/overlay_startup_completed.txt` is missing, it explicitly invokes:
     - `/etc/init.d/startup/S03steamlink-boot-watchdog.sh`
     - `/etc/init.d/startup/S97hidraw-nodes.sh`
     - `/etc/init.d/startup/S97usbip.sh`
     - `/etc/init.d/startup/S98steamlink-ble-proxy.sh`
     - `/etc/init.d/startup/S99steamlink-diagnostics.sh`
     - `/etc/init.d/startup/S99vhusbd.sh`
   - It then creates `/mnt/config/system/overlay_startup_completed.txt` with a timestamp so that on subsequent boots, [`S99steam`](../steamlink/overlay/etc/init.d/startup/S99steam) skips this manual loop, letting `startup.sh`'s standard glob launch everything.
   - Finally, [`S99steam`](../steamlink/overlay/etc/init.d/startup/S99steam) hands off control to the stock Steam Link UI via `/home/steam/rc.local`.

---

## Power Management & Idle Timeouts

Stock Steam Link firmware suspends the device after a period of inactivity, which would stop the background services this repository installs.

To keep headless servers (USB/IP, VirtualHere, BLE proxy, WiFi watchdog) running continuously, the repository provisions:
- [`steamlink/config/system/suspend_timeout_idle.txt`](../steamlink/config/system/suspend_timeout_idle.txt) containing `0`
- [`steamlink/config/system/suspend_timeout_interactive.txt`](../steamlink/config/system/suspend_timeout_interactive.txt) containing `0`

These files disable the power manager's idle sleep timer completely.
