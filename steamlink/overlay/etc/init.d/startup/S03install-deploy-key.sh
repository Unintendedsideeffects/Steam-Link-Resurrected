#!/bin/sh
#
# Install the fleet deployment public key.
#
# Two paths on purpose. The stock sshd_config uses AuthorizedKeysFile
# ".ssh/authorized_keys", which resolves against root's home -- and root's home
# on this firmware is /home/steam, not /root (/root lives on the read-only
# rootfs and cannot be written at all). Writing only the /mnt/config path
# therefore looks successful and still leaves key auth broken, which is exactly
# how one device sat password-only for weeks. Write both: /mnt/config for the
# devices whose sshd_config was pointed at it, /home/steam for stock ones.
set -eu

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVdGjVKQBdoloXMn+dPunO+vjzLS2ZiIy/VWU0yA52S steamlink-deployment'

for DIR in /mnt/config/ssh /home/steam/.ssh; do
    mkdir -p "$DIR" 2>/dev/null || continue
    FILE="$DIR/authorized_keys"
    touch "$FILE" 2>/dev/null || continue
    grep -qxF "$KEY" "$FILE" 2>/dev/null || printf '%s\n' "$KEY" >> "$FILE"
    chmod 700 "$DIR"  2>/dev/null || true
    chmod 600 "$FILE" 2>/dev/null || true
done
