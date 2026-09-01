#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
UI=${STEAMLINK_UI:-whiptail}
DEVICE=${1-}

die() { echo "error: $*" >&2; exit 1; }
ask() {
    REPLY=$("$UI" --title "Steam Link Resurrected" --inputbox "$1" 10 72 "${2-}" 3>&1 1>&2 2>&3) || return $?
}
password() { "$UI" --title "Steam Link Resurrected" --passwordbox "$1" 10 72 3>&1 1>&2 2>&3; }
yesno() { "$UI" --title "Steam Link Resurrected" --yesno "$1" "${2:-12}" 76; }
valid_ipv4() {
    value=$1
    old_ifs=$IFS
    IFS=.
    set -- $value
    IFS=$old_ifs
    [ "$#" -eq 4 ] || return 1
    for octet do
        case "$octet" in ''|*[!0-9]*) return 1;; esac
        [ "$octet" -le 255 ] 2>/dev/null || return 1
    done
}

command -v "$UI" >/dev/null 2>&1 || die "missing TUI program: $UI"
command -v lsblk >/dev/null 2>&1 || die "missing lsblk"
command -v mkfs.vfat >/dev/null 2>&1 || die "missing mkfs.vfat"
command -v openssl >/dev/null 2>&1 || die "missing openssl"
command -v ssh-keygen >/dev/null 2>&1 || die "missing ssh-keygen"

if [ -z "$DEVICE" ]; then
    DEVICE=$(lsblk -nrpo NAME,TYPE,RM,SIZE,MODEL | awk '$2 == "part" && $3 == "1" { print $1; exit }')
fi
[ -b "$DEVICE" ] || die "no removable partition selected"
[ "$(lsblk -ndo TYPE "$DEVICE")" = part ] || die "select a partition, not a whole disk"
REMOVABLE=$(lsblk -ndo RM "$DEVICE")
if [ "$REMOVABLE" != 1 ]; then
    PARENT=$(lsblk -ndo PKNAME "$DEVICE")
    [ -n "$PARENT" ] && [ "$(lsblk -ndo RM "/dev/$PARENT")" = 1 ] || die "selected partition is not on a removable device"
fi
if lsblk -nro NAME,MOUNTPOINTS "$DEVICE" | awk 'NF > 1 && $2 != "" { found=1 } END { exit !found }'; then
    die "unmount all partitions on the selected device first"
fi

ask "Steam Link hostname:" "GuestRoomDesk" || exit 1
HOSTNAME_VALUE=$REPLY
case "$HOSTNAME_VALUE" in ''|*[!A-Za-z0-9_.-]*) die "invalid hostname";; esac
ask "Home Wi-Fi network name (SSID):" || exit 1
WIFI_SSID=$REPLY
WIFI_PASSWORD=$(password "Home Wi-Fi password:") || exit 1
[ -n "$WIFI_SSID" ] || die "Wi-Fi SSID cannot be empty"
SSID_BYTES=$(printf '%s' "$WIFI_SSID" | wc -c | tr -d ' ')
[ "$SSID_BYTES" -le 32 ] || die "Wi-Fi SSID must be at most 32 bytes"
case "$WIFI_SSID$WIFI_PASSWORD" in *[![:print:]]*) die "Wi-Fi values may not contain control characters";; esac
WIFI_PASSWORD_BYTES=$(printf '%s' "$WIFI_PASSWORD" | wc -c | tr -d ' ')
[ "$WIFI_PASSWORD_BYTES" -le 63 ] || die "Wi-Fi password must be at most 63 bytes"
[ "$WIFI_PASSWORD_BYTES" -eq 0 ] || [ "$WIFI_PASSWORD_BYTES" -ge 8 ] || die "WPA Wi-Fi password must be at least 8 bytes"

ENABLE_SSH=1; ENABLE_USBIP=1; ENABLE_VIRTUALHERE=1; ENABLE_MQTT=0; ENABLE_DIAGNOSTICS=0
yesno "Enable SSH?\n\nDisabling SSH is risky because you may lose remote access." || ENABLE_SSH=0
SSH_KEY_PATH=; SSH_PUBLIC_KEY_FILE=
if [ "$ENABLE_SSH" = 1 ]; then
    SSH_KEY_PATH=${STEAMLINK_SSH_KEY_PATH:-/root/.ssh/steamlink-$HOSTNAME_VALUE}
    ask "SSH private key path [$SSH_KEY_PATH]: "
    SSH_KEY_PATH=${REPLY:-$SSH_KEY_PATH}
    case "$SSH_KEY_PATH" in /*) ;; *) die "SSH private key path must be absolute";; esac
fi
yesno "Enable USB/IP?" || ENABLE_USBIP=0
yesno "Enable VirtualHere?" || ENABLE_VIRTUALHERE=0
yesno "Enable Home Assistant MQTT status reporting?" && ENABLE_MQTT=1 || true
yesno "Enable USB diagnostic snapshots?\n\nThis writes to the USB key every 15 seconds." && ENABLE_DIAGNOSTICS=1 || true

SETUP_SSID="SteamLink-Setup-$(printf '%s' "$HOSTNAME_VALUE" | cut -c1-16)"
SETUP_PASSWORD=$(openssl rand -hex 8)
WEB_SECRET=$(openssl rand -hex 16)
OTA_PASSWORD=$(openssl rand -hex 24)
ADDON_DIR=
MQTT_CONFIG=
MOUNTPOINT=
cleanup() {
    rm -f "${MQTT_CONFIG-}"
    if [ -n "$MOUNTPOINT" ]; then
        umount "$MOUNTPOINT" 2>/dev/null || true
        rmdir "$MOUNTPOINT" 2>/dev/null || true
    fi
}
trap cleanup EXIT HUP INT TERM
if [ "$ENABLE_MQTT" = 1 ]; then
    ADDON_DIR=${STEAMLINK_ADDON_DIR-}
    [ -n "$ADDON_DIR" ] || die "MQTT selected but STEAMLINK_ADDON_DIR is not set"
    [ -d "$ADDON_DIR/overlay" ] || die "add-on is missing overlay/: $ADDON_DIR"
    ask "MQTT broker host:" "192.168.86.35" || exit 1
    MQTT_HOST=$REPLY
    ask "MQTT broker port:" "1883" || exit 1
    MQTT_PORT=$REPLY
    ask "MQTT username:" || exit 1
    MQTT_USER=$REPLY
    MQTT_PASSWORD=$(password "MQTT password:") || exit 1
    valid_ipv4 "$MQTT_HOST" || die "MQTT broker host must be an IPv4 address"
    case "$MQTT_PORT" in ''|*[!0-9]*) die "invalid MQTT broker port";; esac
    case "$MQTT_PORT" in ??????*) die "MQTT broker port must be 1-65535";; esac
    [ "$MQTT_PORT" -ge 1 ] && [ "$MQTT_PORT" -le 65535 ] || die "MQTT broker port must be 1-65535"
    case "$MQTT_USER$MQTT_PASSWORD" in *[![:print:]]*) die "MQTT values may not contain control characters";; esac
    MQTT_CONFIG=$(mktemp)
    { printf 'MQTT_HOST=%s\n' "$MQTT_HOST"; printf 'MQTT_PORT=%s\n' "$MQTT_PORT"; printf 'MQTT_USER=%s\n' "$MQTT_USER"; printf 'MQTT_PASSWORD=%s\n' "$MQTT_PASSWORD"; } >"$MQTT_CONFIG"
fi

SUMMARY="Device: $DEVICE\nHostname: $HOSTNAME_VALUE\nSetup Wi-Fi: $SETUP_SSID\nSetup password: $SETUP_PASSWORD\nSetup web secret: $WEB_SECRET\nHome Wi-Fi: $WIFI_SSID\nSSH: $ENABLE_SSH  USB/IP: $ENABLE_USBIP  VirtualHere: $ENABLE_VIRTUALHERE  MQTT: $ENABLE_MQTT  Diagnostics: $ENABLE_DIAGNOSTICS\nSSH private key: ${SSH_KEY_PATH:-disabled}\n\nThe selected partition will be formatted as FAT32."
yesno "$SUMMARY\n\nFORMAT THIS USB KEY?" 20 || exit 1

if [ "$ENABLE_SSH" = 1 ]; then
    [ ! -e "$SSH_KEY_PATH" ] && [ ! -e "$SSH_KEY_PATH.pub" ] || die "SSH key already exists: $SSH_KEY_PATH (choose another path)"
    SSH_KEY_DIR=$(dirname "$SSH_KEY_PATH")
    if [ ! -d "$SSH_KEY_DIR" ]; then
        mkdir -p "$SSH_KEY_DIR"; chmod 700 "$SSH_KEY_DIR"
    fi
    ssh-keygen -q -t ed25519 -N '' -f "$SSH_KEY_PATH" -C "steamlink-$HOSTNAME_VALUE" || die "could not create SSH key"
    chmod 600 "$SSH_KEY_PATH"; chmod 644 "$SSH_KEY_PATH.pub"
    SSH_PUBLIC_KEY_FILE="$SSH_KEY_PATH.pub"
fi

MOUNTPOINT=$(mktemp -d)
umount "$DEVICE" 2>/dev/null || true
mkfs.vfat -F 32 -n STEAMLINK "$DEVICE"
mount "$DEVICE" "$MOUNTPOINT"
STEAMLINK_OTA_PASSWORD="$OTA_PASSWORD" STEAMLINK_ENABLE_SSH="$ENABLE_SSH" STEAMLINK_SSH_PUBLIC_KEY_FILE="$SSH_PUBLIC_KEY_FILE" STEAMLINK_ADDON_DIR="$ADDON_DIR" STEAMLINK_MQTT_CONFIG="$MQTT_CONFIG" "$ROOT/scripts/provision-key.sh" "$MOUNTPOINT" "$HOSTNAME_VALUE"

mkdir -p "$MOUNTPOINT/steamlink/overlay/mnt/config/setup"
{
    printf 'SETUP_SSID=%s\n' "$SETUP_SSID"
    printf 'SETUP_PASSWORD=%s\n' "$SETUP_PASSWORD"
    printf 'WEB_SECRET=%s\n' "$WEB_SECRET"
    printf 'HOSTNAME=%s\n' "$HOSTNAME_VALUE"
    printf 'WIFI_SSID=%s\n' "$WIFI_SSID"
    printf 'WIFI_PASSWORD=%s\n' "$WIFI_PASSWORD"
    printf 'ENABLE_SSH=%s\n' "$ENABLE_SSH"
    printf 'ENABLE_USBIP=%s\n' "$ENABLE_USBIP"
    printf 'ENABLE_VIRTUALHERE=%s\n' "$ENABLE_VIRTUALHERE"
    printf 'ENABLE_MQTT=%s\n' "$ENABLE_MQTT"
    printf 'ENABLE_DIAGNOSTICS=%s\n' "$ENABLE_DIAGNOSTICS"
} >"$MOUNTPOINT/steamlink/overlay/mnt/config/setup/setup.conf"
chmod 600 "$MOUNTPOINT/steamlink/overlay/mnt/config/setup/setup.conf" 2>/dev/null || true

"$ROOT/steamlink/overlay/mnt/config/setup/apply-wifi.sh" "$MOUNTPOINT/steamlink/overlay" "$WIFI_SSID" "$WIFI_PASSWORD"
(cd "$MOUNTPOINT/steamlink" && find config overlay -type f -print | sort | while IFS= read -r file; do sha256sum "$file"; done) >"$MOUNTPOINT/steamlink/PROVISIONED-SHA256SUMS"
(cd "$MOUNTPOINT/steamlink" && sha256sum -c PROVISIONED-SHA256SUMS >/dev/null) || die "generated key failed checksum verification"
sync
"$UI" --title "Steam Link key ready" --msgbox "Provisioned $HOSTNAME_VALUE.\n\nSetup Wi-Fi: $SETUP_SSID\nSetup password: $SETUP_PASSWORD\nSetup web secret: $WEB_SECRET\nSSH key: ${SSH_KEY_PATH:-disabled}" 16 72
if [ "$ENABLE_SSH" = 1 ]; then
    echo "SSH access: ssh -i $SSH_KEY_PATH root@<Steam-Link-IP>"
fi
