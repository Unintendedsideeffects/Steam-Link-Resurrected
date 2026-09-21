# Provisioning & Key Creation Walkthrough

This guide details how to build and provision the FAT32 USB drive used to bootstrap a Valve Steam Link.

---

## Prerequisites

On the Linux host machine used to prepare the key, the following tools must be available in `$PATH`:
- `whiptail` (or custom TUI set via `STEAMLINK_UI`)
- `lsblk`
- `mkfs.vfat` (from `dosfstools`)
- `openssl`
- `ssh-keygen` (from OpenSSH)

---

## Interactive Provisioning (`launch.sh` / `create-key.sh`)

The simplest way to prepare a key is via the interactive launcher:

```sh
sudo ./launch.sh /dev/sdX1
```

> [!CAUTION]
> The selected partition will be formatted as FAT32 (`mkfs.vfat -F 32 -n STEAMLINK`).
> - Pass a partition device (e.g. `/dev/sdb1`), **not** a raw disk (like `/dev/sdb`).
> - The partition must reside on a removable drive (`RM=1`).
> - All partitions on the target drive must be unmounted before running the script.

### TUI Step-by-Step Flow

1. **Hostname Prompt**:
   Choose the device-local hostname (letters, numbers, underscores, dots, and hyphens permitted; default: `GuestRoomDesk`).
   
   ![whiptail hostname prompt](screenshots/tui-hostname.png)

2. **Home Wi-Fi Network (SSID) and Password**:
   Input your local Wi-Fi SSID (1 to 32 printable characters) and WPA passphrase (8 to 63 printable characters, or empty for open networks).
   
   ![whiptail home Wi-Fi SSID prompt](screenshots/tui-wifi.png)

3. **SSH Access Configuration**:
   Choose whether to enable SSH. Disabling SSH prevents remote terminal administration.
   
   ![whiptail Enable SSH confirmation](screenshots/tui-ssh.png)
   
   If SSH is enabled, specify the location on the host machine where the generated Ed25519 private key will be saved (default: `/root/.ssh/steamlink-<hostname>`):
   
   ![whiptail SSH private key path prompt](screenshots/tui-ssh-key.png)
   
   The launcher runs `ssh-keygen -t ed25519` locally, sets file permissions (`0600` for private key, `0644` for public key), and copies **only** the `.pub` file to the USB drive. The private key never touches the USB drive.

4. **Service Selection Prompts**:
   - **USB/IP**: Enable/disable the USB/IP supervisor and kernel modules (default: yes).
   - **VirtualHere**: Enable/disable the bundled VirtualHere daemon (default: yes).
   - **Home Assistant MQTT**: Opt into MQTT status reporting (default: no). If enabled, host, port, username, and password will be prompted. Requires `STEAMLINK_ADDON_DIR`.
   - **USB Diagnostics Snapshots**: Opt into background system state logging to flash every 15s (default: no).

5. **Confirmation & Format**:
   A summary dialog displays the generated setup credentials, hostname, and feature flags before wiping the drive:
   
   ![whiptail pre-format summary](screenshots/tui-summary.png)

6. **Completion Summary**:
   Once formatted, provisioned, and verified against SHA-256 checksums, access credentials are displayed:
   
   ![whiptail provisioning complete dialog](screenshots/tui-complete.png)

---

## Non-Interactive Provisioning (`scripts/provision-key.sh`)

For automation or scripting, [`scripts/provision-key.sh`](../scripts/provision-key.sh) can be called directly without a TUI:

```sh
STEAMLINK_OTA_PASSWORD='replace-with-a-random-device-secret' \
STEAMLINK_ENABLE_SSH=1 \
STEAMLINK_SSH_PUBLIC_KEY_FILE=/path/to/key.pub \
  scripts/provision-key.sh /media/user/STEAMLINK SteamLinkDevice
```

### Environment Variables for `provision-key.sh`

| Variable | Required | Description |
| --- | --- | --- |
| `STEAMLINK_OTA_PASSWORD` | **Yes** | Secret used for authenticated ESPHome native OTA updates. Must not contain control characters. |
| `STEAMLINK_ENABLE_SSH` | No | `1` (default) to keep `enable_ssh.txt` and install public keys; `0` to omit SSH. |
| `STEAMLINK_SSH_PUBLIC_KEY_FILE` | If SSH=1 | Path to the local OpenSSH public key file (`ssh-ed25519`, `ssh-rsa`, or `ecdsa-sha2-*`). |
| `STEAMLINK_ADDON_DIR` | No | Path to an optional addon directory containing an `overlay/` subfolder. |
| `STEAMLINK_MQTT_CONFIG` | No | Path to an MQTT configuration file copied to `/mnt/config/usb-proxy/usb-proxy.conf`. |

---

## Device-Local Configuration Files

The repository source contains example templates (`.example`). During provisioning, real device-specific configuration files are written to `/mnt/config/` on the USB key and are excluded from Git via `.gitignore`:

```text
steamlink/overlay/mnt/config/steamlink-usbip.conf
steamlink/overlay/mnt/config/steamlink-ota.conf
steamlink/overlay/mnt/config/setup/setup.conf
steamlink/overlay/mnt/config/ssh/authorized_keys
steamlink/overlay/mnt/config/ble-proxy/ble-proxy.conf
steamlink/overlay/mnt/config/usb-proxy/usb-proxy.conf
```

- `setup.conf`: Records `SETUP_SSID`, `SETUP_PASSWORD`, `WEB_SECRET`, `HOSTNAME`, `WIFI_SSID`, `WIFI_PASSWORD`, and service enablement flags (`ENABLE_SSH`, `ENABLE_USBIP`, `ENABLE_VIRTUALHERE`, `ENABLE_MQTT`, `ENABLE_DIAGNOSTICS`).
- [`steamlink-usbip.conf`](../steamlink/overlay/mnt/config/steamlink-usbip.conf.example): Records `STEAMLINK_HOSTNAME`.
- [`steamlink-ota.conf`](../steamlink/overlay/mnt/config/steamlink-ota.conf.example): Records `STEAMLINK_OTA_PASSWORD`.
- [`ble-proxy.conf`](../steamlink/overlay/mnt/config/ble-proxy/ble-proxy.conf.example): Copied from the example with default logging flags.

---

## Verification & Manifest Check

At the conclusion of provisioning, [`scripts/provision-key.sh`](../scripts/provision-key.sh) computes SHA-256 hashes of every file in `steamlink/config` and `steamlink/overlay` and writes them to:

```text
<mountpoint>/steamlink/PROVISIONED-SHA256SUMS
```

It validates that `sha256sum -c PROVISIONED-SHA256SUMS` passes before unmounting.

---

## First Boot & Setup AP Flow

1. Insert the USB drive into one of the Steam Link's USB ports and power the unit on.
2. The Steam Link will copy configuration files to `/mnt/config` and merge the overlay into `/mnt/config/overlay`.
3. If the home Wi-Fi or wired network does not connect immediately, [`S04steamlink-setup.sh`](../steamlink/overlay/etc/init.d/startup/S04steamlink-setup.sh) activates an ad-hoc access point:
   - **SSID**: `SteamLink-Setup-<hostname>`
   - **WPA Passphrase**: `SETUP_PASSWORD` (shown in completion TUI / `setup.conf`)
   - **Gateway IP**: `192.168.42.1`
4. Connect a laptop or smartphone to that Wi-Fi network and open `http://192.168.42.1/`.
5. Authenticate using HTTP Basic Auth:
   - **Username**: `admin`
   - **Password**: `WEB_SECRET` (shown in completion TUI / `setup.conf`)
6. From the web portal, you can verify network links, modify Wi-Fi credentials, bind/unbind USB/IP devices, or click **"Disable setup web and AP now"** to stop `uap0` tethering and kill the temporary `httpd` listener.
