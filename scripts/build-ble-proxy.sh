#!/usr/bin/env sh
set -eu

# Rebuild the ARMv7 BLE proxy from pinned upstream sources and place the
# stripped artifact in the Steam Link overlay. No dependency source is vendored
# in this repository; the patch and these pins are the reproducible recipe.

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-"$ROOT/steamlink/overlay/mnt/config/ble-proxy/esphome-linux"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/steamlink-ble-build.XXXXXX")
KEEP_BUILD_DIR=${KEEP_BUILD_DIR:-0}
BUILD_TYPE=${BUILD_TYPE:-release}
NO_STRIP=${NO_STRIP:-0}
cleanup() {
    [ "$KEEP_BUILD_DIR" = 1 ] || rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

ESPHOME_REPO=${ESPHOME_REPO:-https://github.com/yinzara/esphome-linux.git}
ESPHOME_COMMIT=${ESPHOME_COMMIT:-ea405916751780f2611d97ea87c3c52afcd3021a}
ATBM_REPO=${ATBM_REPO:-https://github.com/gtxaspec/atbm-wifi.git}
ATBM_COMMIT=${ATBM_COMMIT:-728e236d26a64907959b5b511af0b0fd8b87c509}
BLUEZ_REPO=${BLUEZ_REPO:-https://github.com/bluez/bluez.git}
BLUEZ_TAG=${BLUEZ_TAG:-5.79}
LIBBLE_REPO=${LIBBLE_REPO:-https://github.com/yinzara/libblepp.git}
LIBBLE_TAG=${LIBBLE_TAG:-v0.0.4}

CC=${CC:-arm-linux-gnueabihf-gcc}
CXX=${CXX:-arm-linux-gnueabihf-g++}
AR=${AR:-arm-linux-gnueabihf-ar}
STRIP=${STRIP:-arm-linux-gnueabihf-strip}
CROSS_PREFIX=${CROSS_PREFIX:-arm-linux-gnueabihf-}
JOBS=${JOBS:-2}

for tool in git make cmake meson ninja "$CC" "$CXX" "$AR" "$STRIP"; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing build tool: $tool" >&2
        exit 1
    }
done

clone_at() {
    repo=$1
    ref=$2
    destination=$3
    git clone --filter=blob:none --no-checkout "$repo" "$destination" >/dev/null
    git -C "$destination" checkout --detach "$ref" >/dev/null
}

SRC="$WORK/esphome-linux"
clone_at "$ESPHOME_REPO" "$ESPHOME_COMMIT" "$SRC"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-gatt-ota.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-reliability.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-api-idle.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-scanner-idempotent.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-address-type.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-nanoleaf-scan.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-gatt-scan-coordination.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-gatt-timeout.patch"
git -C "$SRC" apply "$ROOT/patches/esphome-linux-2026.5.1.patch"

# NimBLE: the upstream helper builds this library inside the atbm tree.
ATBM="$SRC/nimble/atbm-wifi"
clone_at "$ATBM_REPO" "$ATBM_COMMIT" "$ATBM"
cp "$SRC/nimble/Makefile" "$ATBM/Makefile"
mkdir -p "$ATBM/os"
cp -R "$SRC/nimble/os/." "$ATBM/os/"
make -C "$ATBM" all static CROSS_COMPILE="$CROSS_PREFIX" -j"$JOBS"
make -C "$ATBM" install-staging DESTDIR="$SRC/nimble/out"
cp "$ATBM/libnimble.a" "$SRC/nimble/out/lib/libnimble.a"

# BlueZ: only libbluetooth is required. The small repository Makefile avoids
# building bluetoothd and produces both headers and a static archive.
BLUEZ="$SRC/bluez/bluez-$BLUEZ_TAG"
clone_at "$BLUEZ_REPO" "$BLUEZ_TAG" "$BLUEZ"
cp "$SRC/bluez/Makefile" "$BLUEZ/Makefile"
make -C "$BLUEZ" static CC="$CC"
mkdir -p "$SRC/bluez/out/lib" "$SRC/bluez/out/include/bluetooth"
cp "$BLUEZ/libbluetooth.a" "$SRC/bluez/out/lib/libbluetooth.a"
cp "$BLUEZ/lib/"*.h "$SRC/bluez/out/include/bluetooth/"

# libblepp is the GATT transport. Build it as an archive against the two
# archives above, then let Meson link the final executable fully static.
LIBBLE="$SRC/libble/libblepp"
clone_at "$LIBBLE_REPO" "$LIBBLE_TAG" "$LIBBLE"
git -C "$LIBBLE" apply "$ROOT/patches/libblepp-static.patch"
git -C "$LIBBLE" apply "$ROOT/patches/libblepp-address-type.patch"
git -C "$LIBBLE" apply "$ROOT/patches/libblepp-address-type-getadv.patch"
cmake -S "$LIBBLE" -B "$LIBBLE/build-arm-static" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=arm \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DWITH_BLUEZ_SUPPORT=ON \
    -DWITH_NIMBLE_SUPPORT=ON \
    -DWITH_SERVER_SUPPORT=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBLUEZ_LIBRARY="$BLUEZ/libbluetooth.a" \
    -DBLUEZ_INCLUDE_DIR="$SRC/bluez/out/include" \
    -DNIMBLE_LIBRARY="$ATBM/libnimble.a" \
    -DNIMBLE_ROOT="$SRC/nimble/out"
cmake --build "$LIBBLE/build-arm-static" --parallel "$JOBS"
mkdir -p "$SRC/libble/out/usr/include"
cp -R "$LIBBLE/blepp" "$SRC/libble/out/usr/include/"

cat >"$WORK/armhf-cross.txt" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = '/bin/false'

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOF

LDFLAGS=-static meson setup "$WORK/build" "$SRC" --cross-file "$WORK/armhf-cross.txt" \
    -Denable_plugins=true -Denable_bluetooth_proxy=true -Dbuildtype="$BUILD_TYPE"
meson compile -C "$WORK/build" --jobs "$JOBS"

mkdir -p "$(dirname "$OUTPUT")"
if [ "$NO_STRIP" = 1 ]; then
    cp "$WORK/build/esphome-linux" "$OUTPUT"
else
    "$STRIP" --strip-unneeded "$WORK/build/esphome-linux" -o "$OUTPUT"
fi

file "$OUTPUT" | grep -E 'ARM|statically linked' >/dev/null || {
    echo "the output is not a static ARM artifact" >&2
    exit 1
}
if readelf -d "$OUTPUT" 2>/dev/null | grep -q NEEDED; then
    echo "the output unexpectedly has dynamic dependencies" >&2
    exit 1
fi

echo "built $OUTPUT"
sha256sum "$OUTPUT"
