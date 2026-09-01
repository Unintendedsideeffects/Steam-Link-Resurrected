#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: STEAMLINK_OTA_PASSWORD=... [STEAMLINK_ADDON_DIR=... STEAMLINK_MQTT_CONFIG=...] $0 MOUNTPOINT HOSTNAME" >&2
    exit 2
fi

MOUNTPOINT=$1
HOSTNAME_VALUE=$2
OTA_PASSWORD=${STEAMLINK_OTA_PASSWORD-}
ADDON_DIR=${STEAMLINK_ADDON_DIR-}
MQTT_CONFIG=${STEAMLINK_MQTT_CONFIG-}
ENABLE_SSH=${STEAMLINK_ENABLE_SSH-1}
SSH_PUBLIC_KEY_FILE=${STEAMLINK_SSH_PUBLIC_KEY_FILE-}
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

case "$HOSTNAME_VALUE" in
    ''|*[!A-Za-z0-9_.-]*)
        echo "invalid hostname: $HOSTNAME_VALUE" >&2
        exit 2
        ;;
esac

if [ -z "$OTA_PASSWORD" ]; then
    echo "STEAMLINK_OTA_PASSWORD must be set in the environment" >&2
    exit 2
fi
if printf '%s' "$OTA_PASSWORD" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "STEAMLINK_OTA_PASSWORD may not contain control characters" >&2
    exit 2
fi

[ -d "$MOUNTPOINT" ] || { echo "not a directory: $MOUNTPOINT" >&2; exit 1; }
[ "$ENABLE_SSH" = 0 ] || [ "$ENABLE_SSH" = 1 ] || { echo "STEAMLINK_ENABLE_SSH must be 0 or 1" >&2; exit 2; }
if [ "$ENABLE_SSH" = 1 ]; then
    [ -n "$SSH_PUBLIC_KEY_FILE" ] || { echo "SSH is enabled but no public key was supplied" >&2; exit 1; }
    [ -f "$SSH_PUBLIC_KEY_FILE" ] || { echo "missing SSH public key: $SSH_PUBLIC_KEY_FILE" >&2; exit 1; }
    SSH_PUBLIC_KEY=$(awk 'NF { if (++n == 1) first=$0 } END { if (n == 1) print first; else exit 1 }' "$SSH_PUBLIC_KEY_FILE") || { echo "SSH key file must contain exactly one public key" >&2; exit 1; }
    case "$(printf '%s\n' "$SSH_PUBLIC_KEY" | awk '{print $1}')" in
        ssh-ed25519|ssh-rsa|ecdsa-sha2-*) ;;
        *) echo "SSH public key is not an OpenSSH public key: $SSH_PUBLIC_KEY_FILE" >&2; exit 1;;
    esac
    printf '%s\n' "$SSH_PUBLIC_KEY" | ssh-keygen -lf - >/dev/null 2>&1 || { echo "invalid SSH public key: $SSH_PUBLIC_KEY_FILE" >&2; exit 1; }
fi
if [ -n "$ADDON_DIR" ]; then
    [ -d "$ADDON_DIR/overlay" ] || { echo "add-on is missing overlay/: $ADDON_DIR" >&2; exit 1; }
fi
if [ -n "$MQTT_CONFIG" ]; then
    [ -f "$MQTT_CONFIG" ] || { echo "MQTT config is not a file: $MQTT_CONFIG" >&2; exit 1; }
fi
[ -d "$MOUNTPOINT/steamlink" ] || mkdir -p "$MOUNTPOINT/steamlink"

# FAT32 cannot preserve symlinks, so flatten the public tree while copying.
cp -rL "$ROOT/steamlink/." "$MOUNTPOINT/steamlink/"
if [ "$ENABLE_SSH" = 0 ]; then
    rm -f "$MOUNTPOINT/steamlink/config/system/enable_ssh.txt"
fi

if [ -n "$ADDON_DIR" ]; then
    cp -rL "$ADDON_DIR/overlay/." "$MOUNTPOINT/steamlink/overlay/"
fi

BLE_EXAMPLE="$MOUNTPOINT/steamlink/overlay/mnt/config/ble-proxy/ble-proxy.conf.example"
BLE_CONF="$MOUNTPOINT/steamlink/overlay/mnt/config/ble-proxy/ble-proxy.conf"
if [ ! -f "$BLE_CONF" ] && [ -f "$BLE_EXAMPLE" ]; then
    cp "$BLE_EXAMPLE" "$BLE_CONF"
fi

if [ -n "$MQTT_CONFIG" ]; then
    mkdir -p "$MOUNTPOINT/steamlink/overlay/mnt/config/usb-proxy"
    cp -L "$MQTT_CONFIG" "$MOUNTPOINT/steamlink/overlay/mnt/config/usb-proxy/usb-proxy.conf"
    chmod 600 "$MOUNTPOINT/steamlink/overlay/mnt/config/usb-proxy/usb-proxy.conf" 2>/dev/null || true
fi
mkdir -p "$MOUNTPOINT/steamlink/overlay/mnt/config"
{
    echo "# Device-local settings; keep this file out of the public repository."
    echo "STEAMLINK_HOSTNAME=$HOSTNAME_VALUE"
} >"$MOUNTPOINT/steamlink/overlay/mnt/config/steamlink-usbip.conf"
{
    echo "# Device-local secret; keep this file out of the public repository."
    echo "STEAMLINK_OTA_PASSWORD=$OTA_PASSWORD"
} >"$MOUNTPOINT/steamlink/overlay/mnt/config/steamlink-ota.conf"
chmod 600 "$MOUNTPOINT/steamlink/overlay/mnt/config/steamlink-ota.conf" 2>/dev/null || true
if [ "$ENABLE_SSH" = 1 ]; then
    mkdir -p "$MOUNTPOINT/steamlink/overlay/mnt/config/ssh"
    printf '%s\n' "$SSH_PUBLIC_KEY" >"$MOUNTPOINT/steamlink/overlay/mnt/config/ssh/authorized_keys"
    chmod 600 "$MOUNTPOINT/steamlink/overlay/mnt/config/ssh/authorized_keys" 2>/dev/null || true
fi

(
    cd "$MOUNTPOINT/steamlink"
    find config overlay -type f -print | sort | while IFS= read -r file; do
        sha256sum "$file"
    done
) >"$MOUNTPOINT/steamlink/PROVISIONED-SHA256SUMS"

echo "Provisioned $MOUNTPOINT for $HOSTNAME_VALUE"
