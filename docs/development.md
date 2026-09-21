# Development, Build & Verification

This document covers testing procedures, binary provenance, and compiling the BLE proxy binary from source.

---

## Test Suite & Validation Scripts

Before creating a boot key, run the local repository test suite to verify script syntax, directory layouts, and provisioning behaviors:

```sh
# Verify directory layout, required files, and syntax check (sh -n) on all shell scripts
scripts/verify-layout.sh

# Verify non-interactive provisioning, SSH key validation, and checksum manifests
scripts/test-provision-key.sh

# Verify TUI input handling contracts in create-key.sh
scripts/test-create-key-ui.sh
```

---

## Binary Provenance & Verification

The repository ships pre-built ARMv7 binaries and Linux kernel modules required for the Steam Link userspace.

### Integrity Verification
All checked-in binaries are listed with their expected SHA-256 hashes in `artifacts/SHA256SUMS`:

```sh
sha256sum -c artifacts/SHA256SUMS
```

### Components

1. **USB/IP Stack (`steamlink/overlay/mnt/config/usbip/`)**:
   - Binaries: `bin/usbip`, `bin/usbipd`
   - Libraries: `lib/libusbip.so.0.0.1`, `lib/libsysfs.so.2.0.1`
   - Kernel modules: `modules/usbip-core.ko`, `modules/usbip-host.ko`, `modules/vhci-hcd.ko`
   - Helper scripts: `bin/usbip-start`, `bin/usbip-stop`, `bin/usbip-wrapper`, `bin/usbipd-wrapper`
   - Dynamically linked against glibc 2.19 for the Steam Link 32-bit ARM kernel.

2. **VirtualHere Server**:
   - Bundled stock binary at `/home/steam/bin/vhusbdarmsl` on the Steam Link firmware.

3. **ESPHome BLE Proxy (`steamlink/overlay/mnt/config/ble-proxy/esphome-linux`)**:
   - Statically linked ARMv7 ELF executable.
   - Built from pinned upstream components with repository patches.

---

## Building the BLE Proxy from Source

The ESPHome Linux BLE proxy binary can be rebuilt using [`scripts/build-ble-proxy.sh`](../scripts/build-ble-proxy.sh).

### Build Dependencies
On the compilation host, ensure the following cross-compilation tools and build systems are installed:
- `git`, `make`, `cmake`, `meson`, `ninja`
- Cross-compiler toolchain:
  - `arm-linux-gnueabihf-gcc`
  - `arm-linux-gnueabihf-g++`
  - `arm-linux-gnueabihf-ar`
  - `arm-linux-gnueabihf-strip`

### Pinned Upstream Sources
The build script fetches and checks out pinned commits/tags:
- `esphome-linux`: Commit `ea405916751780f2611d97ea87c3c52afcd3021a` (from `https://github.com/yinzara/esphome-linux.git`)
- `atbm-wifi` (NimBLE): Commit `728e236d26a64907959b5b511af0b0fd8b87c509` (from `https://github.com/gtxaspec/atbm-wifi.git`)
- `bluez`: Tag `5.79` (from `https://github.com/bluez/bluez.git`)
- `libblepp`: Tag `v0.0.4` (from `https://github.com/yinzara/libblepp.git`)

### Applied Patches
The script applies patch sets from the [`patches/`](../patches/) directory:
- `esphome-linux-gatt-ota.patch`: Active GATT service client support and native ESPHome authenticated OTA handler.
- `esphome-linux-reliability.patch`: API error handling and connection teardown.
- `esphome-linux-api-idle.patch`: Idle connection timeouts.
- `esphome-linux-scanner-idempotent.patch`: Multi-client reference-counted scanning.
- `esphome-linux-address-type.patch`: BLE random vs public address preservation.
- `esphome-linux-nanoleaf-scan.patch`: Background scan preservation.
- `esphome-linux-gatt-scan-coordination.patch`: Scanning pause during GATT connect to prevent BlueZ command contention.
- `esphome-linux-gatt-timeout.patch`: GATT operation timeouts.
- `esphome-linux-2026.7.3.patch`: API compatibility adjustments.
- `libblepp-static.patch`: Static library build configurations for libblepp.
- `libblepp-address-type.patch` & `libblepp-address-type-getadv.patch`: Address type propagation.

### Executing the Build

```sh
# Run the build script to produce steamlink/overlay/mnt/config/ble-proxy/esphome-linux
scripts/build-ble-proxy.sh

# Verify that the generated binary is a statically linked ARM executable
file steamlink/overlay/mnt/config/ble-proxy/esphome-linux
sha256sum steamlink/overlay/mnt/config/ble-proxy/esphome-linux
```
