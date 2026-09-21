# Startup Hooks & Opt-In Conditions

All boot services provided by this repository reside in [`steamlink/overlay/etc/init.d/startup/`](../steamlink/overlay/etc/init.d/startup/).

---

## Architectural Design Rule: Safe Fleet Idempotence

Every startup hook is engineered to be **inert unless its prerequisite exists** (e.g., an explicit configuration file, marker file, or binary). This ensures that a single unified overlay can be imaged onto all units in a fleet without unwanted services running on devices that do not need them.

---

## Service Catalog

| Script | Opt-in Condition / Trigger | Purpose | Background / Child Process |
|---|---|---|---|
| [`S01steamlink-ntp-sync.sh`](../steamlink/overlay/etc/init.d/startup/S01steamlink-ntp-sync.sh) | Always runs | Periodic background clock synchronization | Background subshell daemon with PID file `/var/run/steamlink-ntp-sync.pid` |
| [`S02hostname`](../steamlink/overlay/etc/init.d/startup/S02hostname) | `/mnt/config/steamlink-usbip.conf` contains valid `STEAMLINK_HOSTNAME` | Sets system hostname via `/bin/hostname` | Exits synchronously immediately |
| [`S03install-deploy-key.sh`](../steamlink/overlay/etc/init.d/startup/S03install-deploy-key.sh) | Always runs | Injects fleet deployment public SSH key | Exits synchronously immediately |
| [`S03steamlink-boot-watchdog.sh`](../steamlink/overlay/etc/init.d/startup/S03steamlink-boot-watchdog.sh) | `/mnt/config/system/enable_lan_factory_reset_watchdog.txt` exists | Waits 10 minutes for `eth0` IP; on failure writes USB factory reset marker | Background subshell daemon with PID file `/var/run/steamlink-boot-watchdog.pid` |
| [`S04steamlink-setup.sh`](../steamlink/overlay/etc/init.d/startup/S04steamlink-setup.sh) | `/mnt/config/setup/setup.conf` exists and `/mnt/config/setup/disable-setup-web.txt` does **not** exist | Brings up Wi-Fi AP tethering and BusyBox `httpd` on `192.168.42.1:80` | Background monitor loop with PID file `/var/run/steamlink-setup-web.pid` |
| [`S95wifi-watchdog.sh`](../steamlink/overlay/etc/init.d/startup/S95wifi-watchdog.sh) | ConnMan has an active Wi-Fi service **and** default route is on a wireless interface (`mlan0`, `wlan0`, `wlp*`) | Multi-stage health check and automatic escalation/recovery for headless Wi-Fi links | Background subshell daemon with PID file `/var/run/wifi-watchdog.pid` |
| [`S96steamlink-device-status.sh`](../steamlink/overlay/etc/init.d/startup/S96steamlink-device-status.sh) | `/mnt/config/bin/steamlink-device-status` is executable **and** `/mnt/config/usb-proxy/usb-proxy.conf` is non-empty | Supervisor loop running the native USB status reporter | Background subshell loop with PID file `/var/run/steamlink-device-status.pid` |
| [`S97hidraw-nodes.sh`](../steamlink/overlay/etc/init.d/startup/S97hidraw-nodes.sh) | Always runs | Scans `/sys/class/hidraw/hidraw*` and creates missing `/dev/hidrawN` device nodes via `mknod` | Exits synchronously immediately |
| [`S97usbip.sh`](../steamlink/overlay/etc/init.d/startup/S97usbip.sh) | `ENABLE_USBIP=1` (the default when unset) and `/mnt/config/setup/disable-usbip.txt` does not exist | Supervisor ensuring kernel modules are loaded and `usbipd` is listening on TCP port 3240 | Background supervisor loop |
| [`S98steamlink-ble-proxy.sh`](../steamlink/overlay/etc/init.d/startup/S98steamlink-ble-proxy.sh) | `/mnt/config/ble-proxy/esphome-linux` is executable | Supervisor for the ESPHome BLE proxy daemon | Background supervisor loop with PID file `/var/run/steamlink-ble-proxy.pid` |
| [`S99steam`](../steamlink/overlay/etc/init.d/startup/S99steam) | Always runs | First-boot overlay hook anchor, then calls `/home/steam/rc.local` | Exits synchronously after running scripts or starts `/home/steam/rc.local` |
| [`S99steamlink-diagnostics.sh`](../steamlink/overlay/etc/init.d/startup/S99steamlink-diagnostics.sh) | `ENABLE_DIAGNOSTICS=1` in `/mnt/config/setup/setup.conf` | Periodic (15s) system health snapshot written to flash | Background subshell loop with PID file `/var/run/steamlink-diagnostics.pid` |
| [`S99vhusbd.sh`](../steamlink/overlay/etc/init.d/startup/S99vhusbd.sh) | `ENABLE_VIRTUALHERE=1` (the default when unset) and `/home/steam/bin/vhusbdarmsl` is executable | Starts the firmware's bundled VirtualHere server on TCP port 7575 | Background process with PID file `/var/run/vhusbdarm.pid` |

---

## Detailed Service Operations

### `S01steamlink-ntp-sync.sh`
Steam Link devices have no real-time clock (RTC) battery; hardware clocks drift or reset on power loss. This script queries `pool.ntp.org` and `time.cloudflare.com` sequentially using `/bin/ntpd -q -n -p`. Once synchronized, it sleeps for 3600 seconds (1 hour); if unreachable, it retries every 60 seconds.

### `S03steamlink-boot-watchdog.sh`
Used for recovery on unattended devices. If `/mnt/config/system/enable_lan_factory_reset_watchdog.txt` is created, it starts a 600-second (10-minute) timer waiting for `eth0` to obtain an IP address. If no IP address is assigned by the deadline, it mounts the USB key, logs kernel buffer dumps and network interface stats to `boot-watchdog-failure.log`, disables itself, and creates `/factory_reset.txt` on the USB key root. It deliberately does not issue a reboot command; the reset triggers upon the next manual power cycle.

### `S04steamlink-setup.sh`
Provides a temporary browser configuration environment. It restores Wi-Fi credentials from `/mnt/config/setup/steamlinkhome.config` to `/var/lib/connman/` if present. If no external network address is detected on any interface (excluding loopback and `uap0`), it configures `uap0` with `192.168.42.1`, runs `connmanctl tether wifi on "$SETUP_SSID" "$SETUP_PASSWORD"`, generates a random CSRF token in `/var/run/steamlink-setup.csrf`, creates an HTTP Basic authentication file `/mnt/config/setup/httpd.conf` with user `admin` and password `WEB_SECRET`, and launches BusyBox `httpd`. A background loop polls network status every 10 seconds; once a non-link-local IP is acquired or when `/mnt/config/setup/disable-setup-web.txt` is created, it calls `stop-web.sh`.

### `S95wifi-watchdog.sh`
Designed for units whose sole network link is Wi-Fi. It queries ConnMan and routing tables to determine the default gateway (`GW`), interface (`UP`), and service (`SVC`). Every 15 seconds, it pings the default gateway. If health checks fail consecutively, it steps through an escalation ladder:
1. **Level 1 (4 failures / 1 min)**: Runs `connmanctl connect $SVC`.
2. **Level 2 (8 failures / 2 min)**: Kills `connmand` (`killall connmand`); the firmware supervisor restarts it.
3. **Level 3 (14 failures / 3.5 min)**: Reloads the Wi-Fi hardware stack:
   - Kills `wpa_supplicant`
   - Unloads kernel modules: `rmmod sd8897`, `rmmod 8897mlan`
   - Triggers hardware reset: `/bin/wifi_reset`
   - Triggers SDIO bus rescan: `echo 1 > /sys/devices/soc.0/f7ab0000.sdhci/mmc_host/mmc0/rescan`
   - Reruns `/etc/init.d/start_wifi.sh` and `/etc/init.d/wpa_supplicant.sh`
   - Restarts `connmand` and reconnects to the service.
4. **Level 4 (24 failures / 6 min)**: Reboots the device via `/etc/init.d/reboot.sh`. Reboots are strictly rate-limited to at most once per 3600 seconds (1 hour) recorded in `/mnt/config/log/wifi-watchdog.lastreboot`.

All state transitions are logged to `/mnt/config/log/wifi-watchdog.log`.

### `S97usbip.sh`
Checks every 10 seconds whether TCP port 3240 is open (`netstat -lnt | grep -q ':3240 '`). If down, it executes `/mnt/config/usbip/bin/usbip-start`, which loads `usbip-core.ko`, `usbip-host.ko`, and `vhci-hcd.ko` via `insmod`, and launches `/mnt/config/usbip/bin/usbipd -D` with `LD_LIBRARY_PATH=/mnt/config/usbip/lib`. Supervises and rotates `/mnt/config/log/usbip-supervisor.log` at 10 MB.

### `S98steamlink-ble-proxy.sh`
Supervisor for [`/mnt/config/ble-proxy/esphome-linux`](../steamlink/overlay/mnt/config/ble-proxy/esphome-linux).
- **Environment export**: Reads `LOG_LEVEL`, `BLE_PROXY_VERBOSE`, and `ESPHOME_API_VERBOSE` from `/mnt/config/ble-proxy/ble-proxy.conf` (or `.conf.example`) and exports them.
- **HCI adapter reset**: Toggles `hciconfig hci0 down` and `hciconfig hci0 up` before each launch to prevent "Command Disallowed" errors from stuck adapter states.
- **Maintenance tasks**: Runs a background log rotator that performs copy-truncate on `/mnt/config/log/steamlink-ble-proxy.log` when it exceeds 10 MB. Also spawns a 24-hour cleanup worker that removes old binary backup artifacts (`/mnt/config/ble-proxy/esphome-linux.before-project-metadata-fix-20260722`) once the proxy has been consistently healthy.

### `S99vhusbd.sh`
Launches the Steam Link's stock bundled VirtualHere server binary at `/home/steam/bin/vhusbdarmsl` with `-b` (background daemon mode). Supervises and rotates its log `/mnt/config/log/vhusbd.log` at 10 MB.
