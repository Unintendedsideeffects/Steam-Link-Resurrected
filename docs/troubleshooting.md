# Troubleshooting & Firmware Traps

This document compiles firmware-specific quirks, edge cases, and pitfalls discovered on live Steam Link hardware.

---

## 1. Startup Script Glob Matches All `S*` Files

The Steam Link startup runner `/etc/init.d/startup.sh` executes scripts using:

```sh
for script in $STARTUPDIR/S*; do
    [ -x "$script" ] && "$script"
done
```

> [!CAUTION]
> Because the glob is `$STARTUPDIR/S*`, any executable file beginning with the letter `S` is executed.
> A file named `S97usbip.sh.bak`, `S97usbip.sh.pre-fix`, or `S97usbip.sh.old` is **not** an inert backup. It will be run as a second, concurrent instance of the service on every boot.
>
> **Rule**: Never leave backup scripts inside `/etc/init.d/startup/`. Keep them in another directory, or rename them without an `S` prefix (e.g. `bak.S97usbip.sh`).

---

## 2. No Python Interpreter Exists

The stock Steam Link firmware has **no Python runtime**:
- Executing `python`, `python2`, or `python3` fails with command not found or writes `No python interpreter found` to logs.
- Any services, plugins, or tools written in Python will not run on this firmware.
- This repository contains exclusively POSIX shell scripts and native ARMv7 binaries.

---

## 3. Signal Names in `/bin/ash` Traps

The default shell `/bin/ash` (BusyBox) does not accept signal names in `trap` statements:

```sh
# BROKEN: fails with "trap: INT: bad trap"
trap cleanup INT TERM
```

Because this failure is non-fatal, `/bin/ash` prints a warning and silently leaves the trap unregistered.

**Solution**: Use numeric signal values:
```sh
# CORRECT: 2 = SIGINT, 15 = SIGTERM
trap cleanup 2 15
trap 'exit 143' 2 15
```

---

## 4. Subshell PID Expansion (`$$` vs `$!`)

When running a command or subshell in the background, `$$` inside the subshell expands to the **parent shell's PID**, not the subshell's PID:

```sh
# BROKEN: writes the parent PID to the pidfile!
(
    echo $$ > /var/run/myservice.pid
    while true; do ...; done
) &
```

If the parent process exits immediately (as startup hooks do), the PID recorded in the pidfile belongs to an exited process. A subsequent single-instance check:
```sh
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then exit 0; fi
```
will always fail, allowing multiple instances of the loop to spawn on every run.

**Solution**: Record `$!` in the parent shell immediately after launching the background task:
```sh
(
    while true; do ...; done
) &
echo $! > /var/run/myservice.pid
```

---

## 5. Root Home Directory is `/home/steam`, Not `/root`

- `/root` is located on the read-only yaffs2 flash rootfs. It cannot be written to.
- The root user's home directory in `/etc/passwd` is `/home/steam`.
- The OpenSSH configuration `/etc/sshd_config` specifies:
  ```text
  AuthorizedKeysFile .ssh/authorized_keys
  ```
  which evaluates to `/home/steam/.ssh/authorized_keys`.
- Writing only to `/mnt/config/ssh/authorized_keys` leaves stock OpenSSH key authentication failing. See [`docs/ssh.md`](../docs/ssh.md) for full details.

---

## 6. UnionFS Overlay Persistence & In-Place Script Modification

- `/` is read-only.
- `/etc`, `/var`, `/home/steam`, and `/usr/local` are unionfs mounts backed by `/mnt/config/overlay/<dir>`.
- Any file written to `/etc/init.d/startup/` persists automatically across reboots in flash.
- **Do not edit a running shell script in place**: BusyBox `/bin/sh` reads scripts incrementally as they execute. Overwriting an active script in place can cause the shell interpreter to read corrupted byte offsets.
- **Solution**: Always write new script contents to a temporary file on the same filesystem and replace the target atomically using `mv`:
  ```sh
  cat > /etc/init.d/startup/S97usbip.sh.tmp << 'EOF'
  ...
  EOF
  chmod 755 /etc/init.d/startup/S97usbip.sh.tmp
  mv /etc/init.d/startup/S97usbip.sh.tmp /etc/init.d/startup/S97usbip.sh
  ```

---

## 7. Startup Scripts Only Take Effect on the Next Boot

Changes made to files in `/etc/init.d/startup/` do not retroactively alter the processes currently running in memory. Any modifications will take effect upon the next system boot (or by manually executing the modified script or restarting the service daemon).

---

## 8. Bluetooth Adapter Contention (`hci0`)

The BLE proxy daemon ([`esphome-linux`](../steamlink/overlay/mnt/config/ble-proxy/esphome-linux)) requires exclusive access to the Bluetooth HCI controller `hci0`.

- Do not run `bluetoothctl`, `hcitool`, `btmon`, or external scanner scripts concurrently while the proxy is active. Running external scan commands results in HCI error `Command Disallowed`.
- The proxy handles GATT connections by pausing its internal BlueZ scan loop, performing the libblepp GATT connection, and resuming scanning afterwards to avoid command collisions.
- The startup script [`S98steamlink-ble-proxy.sh`](../steamlink/overlay/etc/init.d/startup/S98steamlink-ble-proxy.sh) cycles `hciconfig hci0 down` and `hciconfig hci0 up` before restarting the proxy to reset controller state after abnormal terminations.

---

## 9. Examining Log Files

When troubleshooting a misbehaving service on the Steam Link, check the persistent log files stored in `/mnt/config/log/`:

- `/mnt/config/log/wifi-watchdog.log`: Detailed log of Wi-Fi health checks, gateway pings, and escalation steps (L1 through L4). Check this log to verify whether Wi-Fi drops are occurring.
- `/mnt/config/log/usbip-supervisor.log` and `/mnt/config/log/usbip.log`: Status of kernel module insertion and `usbipd` execution.
- `/mnt/config/log/steamlink-ble-proxy.log`: ESPHome Native API connections, BLE scan events, and error traces.
- `/mnt/config/log/vhusbd-startup.log` and `/mnt/config/log/vhusbd.log`: VirtualHere server daemon output.
- `/mnt/config/log/setup-httpd.log` and `/mnt/config/log/setup-wifi.log`: Diagnostic logs from the setup AP web server and ConnMan tethering.
- `/mnt/config/log/boot-watchdog.log`: Ethernet link watchdog events and factory reset triggers.
- `/mnt/config/log/steamlink-diagnostics.log`: Comprehensive system snapshots (CPU, memory, kernel dmesg, USB topology) if `ENABLE_DIAGNOSTICS=1`.
