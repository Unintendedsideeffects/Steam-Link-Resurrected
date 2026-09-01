#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/steamlink-bootstrap-provision-test.XXXXXX)
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
cmp "$WORK/host-key.pub" overlay/mnt/config/ssh/authorized_keys
test ! -e overlay/mnt/config/ssh/host-key
test ! -e overlay/mnt/config/usb-proxy/usb-proxy.conf
if find . -type f | grep -Eiq 'python'; then
    echo 'Python file found in base provisioned key' >&2
    exit 1
fi

echo 'bootstrap provisioning OK'
