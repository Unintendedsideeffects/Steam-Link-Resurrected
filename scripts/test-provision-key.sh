#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/steamlink-bootstrap-provision-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
KEY="$WORK/key"
mkdir -p "$KEY"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/host-key" >/dev/null

STEAMLINK_OTA_PASSWORD='bootstrap-provision-test-secret' \
STEAMLINK_SSH_PUBLIC_KEY_FILE="$WORK/host-key.pub" \
    "$ROOT/scripts/provision-key.sh" "$KEY" BootstrapTest >/dev/null

cd "$KEY/steamlink"
sha256sum -c PROVISIONED-SHA256SUMS >/dev/null
test -f overlay/etc/init.d/startup/S04steamlink-setup.sh
test -f overlay/mnt/config/setup/www/cgi-bin/setup.cgi
test -f overlay/mnt/config/setup/apply-wifi.sh
test -f overlay/mnt/config/steamlink-usbip.conf
test -f overlay/mnt/config/ble-proxy/ble-proxy.conf
cmp "$WORK/host-key.pub" overlay/mnt/config/ssh/authorized_keys
test ! -e overlay/mnt/config/ssh/host-key
test ! -e overlay/mnt/config/usb-proxy/usb-proxy.conf
BAD="$WORK/bad-key"
mkdir "$BAD"
if STEAMLINK_OTA_PASSWORD='bootstrap-provision-test-secret' \
    STEAMLINK_SSH_PUBLIC_KEY_FILE="$WORK/host-key" \
    "$ROOT/scripts/provision-key.sh" "$BAD" PrivateKeyTest >/dev/null 2>&1; then
    echo 'private SSH key was accepted as a public key' >&2
    exit 1
fi
test -z "$(find "$BAD" -mindepth 1 -print -quit)"
cat "$WORK/host-key.pub" "$WORK/host-key" >"$WORK/combined-key"
mkdir "$WORK/combined"
if STEAMLINK_OTA_PASSWORD='bootstrap-provision-test-secret' \
    STEAMLINK_SSH_PUBLIC_KEY_FILE="$WORK/combined-key" \
    "$ROOT/scripts/provision-key.sh" "$WORK/combined" CombinedKeyTest >/dev/null 2>&1; then
    echo 'combined SSH key file was accepted' >&2
    exit 1
fi
test ! -e "$WORK/combined/steamlink/overlay/mnt/config/ssh/authorized_keys"
STRAY="$ROOT/steamlink/overlay/mnt/config/ssh/authorized_keys"
STRAY_OTA="$ROOT/steamlink/overlay/mnt/config/steamlink-ota.conf"
STRAY_HOST="$ROOT/steamlink/overlay/mnt/config/steamlink-usbip.conf"
STRAY_SETUP="$ROOT/steamlink/overlay/mnt/config/setup/setup.conf"
STRAY_BLE="$ROOT/steamlink/overlay/mnt/config/ble-proxy/ble-proxy.conf"
cleanup_stray() {
    rm -f "$STRAY" "$STRAY_OTA" "$STRAY_HOST" "$STRAY_SETUP" "$STRAY_BLE"
    rmdir "$(dirname "$STRAY")" 2>/dev/null || true
}
trap 'cleanup_stray; rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$(dirname "$STRAY")" "$(dirname "$STRAY_SETUP")"
echo 'ssh-ed25519 AAAAstray stray@host' >"$STRAY"
echo 'STEAMLINK_OTA_PASSWORD=stray-device-secret' >"$STRAY_OTA"
echo 'STEAMLINK_HOSTNAME=OtherDevice' >"$STRAY_HOST"
echo 'WIFI_PASSWORD=stray-wifi' >"$STRAY_SETUP"
echo 'LOG_LEVEL=Debug' >"$STRAY_BLE"
mkdir "$WORK/stray"
STEAMLINK_OTA_PASSWORD='bootstrap-provision-test-secret' \
STEAMLINK_ENABLE_SSH=0 \
    "$ROOT/scripts/provision-key.sh" "$WORK/stray" StrayTest >/dev/null
STRAY_KEY="$WORK/stray/steamlink/overlay/mnt/config"
if [ -e "$STRAY_KEY/ssh/authorized_keys" ]; then
    echo 'stray authorized_keys was copied onto the key' >&2
    exit 1
fi
if [ -e "$STRAY_KEY/setup/setup.conf" ]; then
    echo 'stray setup.conf was copied onto the key' >&2
    exit 1
fi
grep -q 'STEAMLINK_OTA_PASSWORD=bootstrap-provision-test-secret' "$STRAY_KEY/steamlink-ota.conf"
grep -q 'STEAMLINK_HOSTNAME=StrayTest' "$STRAY_KEY/steamlink-usbip.conf"
grep -q '^LOG_LEVEL=Warning$' "$STRAY_KEY/ble-proxy/ble-proxy.conf"
cleanup_stray
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
cd "$KEY/steamlink"

if find . -type f | grep -Eiq 'python'; then
    echo 'Python file found in base provisioned key' >&2
    exit 1
fi

echo 'bootstrap provisioning OK'
