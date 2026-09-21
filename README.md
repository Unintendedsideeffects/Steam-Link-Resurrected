# Steam Link Resurrected (`steamlink-usbip-bootstrap`)

This repository builds a FAT32 USB bootstrap drive that provisions a Valve Steam Link device with:
- **SSH access** with host-generated key pairs
- **USB/IP server & supervisor** (TCP port `3240`) for forwarding USB devices to remote hosts
- **ESPHome Bluetooth Proxy** (TCP port `6053`) supporting active GATT connections (reads, writes, notifications) and native authenticated OTA updates (TCP port `8082`)
- **VirtualHere USB Server** (TCP port `7575`) using the firmware's bundled daemon
- **Wi-Fi Uplink Watchdog** providing automatic connection recovery and rate-limited reboot escalation
- **Device-local hostname configuration** and network setup web portal (`192.168.42.1`)
- **Power management overrides** disabling the firmware's idle and interactive suspend timers
- Optional native MQTT device status reporter

Standard Steam Link streaming features remain functional alongside these background services.

---

## Quick Start: Building a Boot Key

### 1. Requirements on the Build Machine
The host preparation script requires Linux with:
`whiptail`, `lsblk`, `mkfs.vfat` (`dosfstools`), `openssl`, and `ssh-keygen`.

### 2. Interactive Setup (TUI)
Insert a USB flash drive (must be a removable drive, e.g. `/dev/sdb1`), ensure all partitions on it are unmounted, and run:

```sh
sudo ./launch.sh /dev/sdb1
```

The script will prompt for:
1. Target **Hostname** (default: `GuestRoomDesk`)
2. Local **Home Wi-Fi SSID** and passphrase
3. **SSH enablement** and local destination for the private key (e.g. `/root/.ssh/steamlink-GuestRoomDesk`)
4. Feature flags for **USB/IP**, **VirtualHere**, **MQTT reporting**, and **Diagnostics**
5. Confirmation before formatting the partition as FAT32 (`mkfs.vfat -F 32 -n STEAMLINK`)

*For a full walkthrough with dialog screenshots, see [`docs/provisioning.md`](docs/provisioning.md).*

### 3. Non-Interactive / Scripted Setup
To provision an existing mount point non-interactively:

```sh
STEAMLINK_OTA_PASSWORD='replace-with-a-random-secret' \
STEAMLINK_ENABLE_SSH=1 \
STEAMLINK_SSH_PUBLIC_KEY_FILE=/path/to/key.pub \
  scripts/provision-key.sh /mnt/usbkey TargetHostname
```

### 4. First Boot & Setup AP
1. Insert the USB drive into the Steam Link and connect power.
2. The device copies configuration and startup hooks to `/mnt/config` on flash memory.
3. If the home Wi-Fi network does not connect immediately, the device launches an ad-hoc Wi-Fi access point:
   - **SSID**: `SteamLink-Setup-<hostname>`
   - **Password**: Shown in TUI completion screen (and saved in `/mnt/config/setup/setup.conf`)
   - **Web Portal**: `http://192.168.42.1/` (HTTP Basic Auth username: `admin`, password: `WEB_SECRET`)
4. Once configured, disable the setup web portal or wait for the unit to join your home network.

---

## Network Services & Ports

Once booted and connected to your network, the following services listen on the Steam Link:

| Port | Protocol | Service | Managed By |
|---|---|---|---|
| `22` | TCP | OpenSSH Daemon | Stock firmware (`/etc/sshd_config`) + [`S03install-deploy-key.sh`](steamlink/overlay/etc/init.d/startup/S03install-deploy-key.sh) |
| `3240` | TCP | USB/IP Daemon (`usbipd`) | [`S97usbip.sh`](steamlink/overlay/etc/init.d/startup/S97usbip.sh) / [`usbip-start`](steamlink/overlay/mnt/config/usbip/bin/usbip-start) |
| `6053` | TCP | ESPHome Native API (BLE Proxy) | [`S98steamlink-ble-proxy.sh`](steamlink/overlay/etc/init.d/startup/S98steamlink-ble-proxy.sh) / [`esphome-linux`](steamlink/overlay/mnt/config/ble-proxy/esphome-linux) |
| `7575` | TCP | VirtualHere Server (`vhusbdarmsl`) | [`S99vhusbd.sh`](steamlink/overlay/etc/init.d/startup/S99vhusbd.sh) |
| `8082` | TCP | ESPHome Native OTA Updates | [`esphome-linux`](steamlink/overlay/mnt/config/ble-proxy/esphome-linux) |
| `80` | TCP | Setup Web Interface (`192.168.42.1` only) | [`S04steamlink-setup.sh`](steamlink/overlay/etc/init.d/startup/S04steamlink-setup.sh) (temporary, on `uap0`) |

---

## Documentation Index

Detailed reference documentation is organized across specialized documents:

- **[`docs/architecture.md`](docs/architecture.md)**:
  Filesystem layout (yaffs2 read-only `/`, unionfs overlays), the boot sequence, `startup.sh` glob execution, late-anchor `S99steam`, and power management idle timers.
- **[`docs/provisioning.md`](docs/provisioning.md)**:
  Full walkthrough of `launch.sh` and `create-key.sh` TUI dialogs with screenshots, environment variables for `provision-key.sh`, device-local secret handling, and the setup AP.
- **[`docs/startup-hooks.md`](docs/startup-hooks.md)**:
  Catalogue of all scripts in `/etc/init.d/startup/`, their specific opt-in prerequisites, execution flags, and background processes.
- **[`docs/ssh.md`](docs/ssh.md)**:
  Key management, the root home directory pitfall (`/home/steam` vs `/root`), dual key installation, and SSH connections.
- **[`docs/troubleshooting.md`](docs/troubleshooting.md)**:
  Critical live-firmware discoveries: `S*` startup glob matching, lack of Python, BusyBox ash trap numbers, subshell PID traps, script editing rules, and persistent log file locations.
- **[`docs/development.md`](docs/development.md)**:
  Running test suites (`verify-layout.sh`, `test-provision-key.sh`, `test-create-key-ui.sh`), binary provenance (`artifacts/SHA256SUMS`), and compiling the static BLE proxy from source.

---

## Verification & Testing

Verify repository scripts and layout consistency locally with:

```sh
scripts/verify-layout.sh
scripts/test-provision-key.sh
scripts/test-create-key-ui.sh
sha256sum -c artifacts/SHA256SUMS
```
