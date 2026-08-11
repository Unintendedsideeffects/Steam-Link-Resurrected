#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: STEAMLINK_OTA_PASSWORD=... $0 MOUNTPOINT HOSTNAME" >&2
    exit 2
fi

MOUNTPOINT=$1
HOSTNAME_VALUE=$2
OTA_PASSWORD=${STEAMLINK_OTA_PASSWORD-}
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

case "$HOSTNAME_VALUE" in
    ''|*[!A-Za-z0-9_.-]*)
        echo "invalid hostname: $HOSTNAME_VALUE" >&2
        exit 2
        ;;
esac

case "$OTA_PASSWORD" in
    '')
        echo "STEAMLINK_OTA_PASSWORD must be set in the environment" >&2
        exit 2
        ;;
    *[\r\n]*)
        echo "STEAMLINK_OTA_PASSWORD may not contain newlines" >&2
        exit 2
        ;;
esac

[ -d "$MOUNTPOINT" ] || { echo "not a directory: $MOUNTPOINT" >&2; exit 1; }
[ -d "$MOUNTPOINT/steamlink" ] || mkdir -p "$MOUNTPOINT/steamlink"

# FAT32 cannot preserve symlinks, so flatten the public tree while copying.
cp -rL "$ROOT/steamlink/." "$MOUNTPOINT/steamlink/"
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

(
    cd "$MOUNTPOINT/steamlink"
    find config overlay -type f -print | sort | while IFS= read -r file; do
        sha256sum "$file"
    done
) >"$MOUNTPOINT/steamlink/PROVISIONED-SHA256SUMS"

echo "Provisioned $MOUNTPOINT for $HOSTNAME_VALUE"
