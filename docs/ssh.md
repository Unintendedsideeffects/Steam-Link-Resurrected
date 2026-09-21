# SSH Architecture & Key Management

This document details how remote SSH access is provisioned and authenticated on the Steam Link.

---

## The Root Home Directory Trap: `/home/steam` vs `/root`

On standard Linux systems, the root account's home directory is `/root`. However, on the Steam Link:

1. **`/root` is on the read-only flash filesystem**:
   - Any attempt to write to `/root` or `/root/.ssh` fails with `Read-only file system`.
2. **`root`'s `$HOME` evaluates to `/home/steam`**:
   - The passwd entry for root sets `/home/steam` as its home directory.
   - The stock `/etc/sshd_config` configures:
     ```text
     AuthorizedKeysFile .ssh/authorized_keys
     ```
   - Because `sshd` resolves relative paths against the logging-in user's home directory, root's authorized keys file resolves to:
     ```text
     /home/steam/.ssh/authorized_keys
     ```

> [!IMPORTANT]
> If a deployment writes an SSH key only to `/mnt/config/ssh/authorized_keys`, the stock `sshd` daemon will **not** find it. Writing only to `/mnt/config/ssh/authorized_keys` appears to succeed during key preparation, but leaves key authentication non-functional, leaving the device password-only.

---

## How Keys Are Installed

Key distribution is handled across two phases:

### 1. Key Creation (`scripts/create-key.sh` & `scripts/provision-key.sh`)
When SSH is enabled during key preparation:
- The script checks for the existence of `steamlink/config/system/enable_ssh.txt` (which instructs the firmware bootloader to enable the SSH daemon). If SSH is disabled, this file is deleted.
- An Ed25519 key pair is generated locally on the workstation (e.g. `~/.ssh/steamlink-<hostname>`).
- Only the **public key** is copied to the USB drive at:
  ```text
  steamlink/overlay/mnt/config/ssh/authorized_keys
  ```
  The private key is never written to the USB drive.

### 2. Boot-Time Key Injection (`S03install-deploy-key.sh`)
During every boot, [`steamlink/overlay/etc/init.d/startup/S03install-deploy-key.sh`](../steamlink/overlay/etc/init.d/startup/S03install-deploy-key.sh) executes.

It writes the deployment public key to **both** paths:
- `/mnt/config/ssh/authorized_keys` (for firmware or tools configured to use this path)
- `/home/steam/.ssh/authorized_keys` (for stock OpenSSH `sshd`)

```sh
for DIR in /mnt/config/ssh /home/steam/.ssh; do
    mkdir -p "$DIR" 2>/dev/null || continue
    FILE="$DIR/authorized_keys"
    touch "$FILE" 2>/dev/null || continue
    grep -qxF "$KEY" "$FILE" 2>/dev/null || printf '%s\n' "$KEY" >> "$FILE"
    chmod 700 "$DIR"  2>/dev/null || true
    chmod 600 "$FILE" 2>/dev/null || true
done
```

Because `/home/steam` is a unionfs mount backed by `/mnt/config/overlay/home/steam`, changes made to `/home/steam/.ssh/authorized_keys` persist across reboots.

---

## Connecting Over SSH

Once the Steam Link is booted and connected to your network:

```sh
ssh -i /path/to/private_key root@<steam-link-ip>
```

Replace `/path/to/private_key` with the path selected during provisioning (e.g. `~/.ssh/steamlink-GuestRoomDesk`).
