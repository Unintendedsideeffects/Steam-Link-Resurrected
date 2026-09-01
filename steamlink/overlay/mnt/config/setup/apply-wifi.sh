#!/bin/sh
set -eu

DEST=${1-}
SSID=${2-}
PASS=${3-}
[ -n "$DEST" ] && [ -n "$SSID" ] || { echo "usage: $0 DEST SSID [PASSWORD]" >&2; exit 2; }
bytes=$(printf '%s' "$SSID" | wc -c | tr -d ' ')
[ "$bytes" -ge 1 ] && [ "$bytes" -le 32 ] || { echo "Wi-Fi SSID must be 1-32 bytes" >&2; exit 2; }
case "$SSID$PASS" in *[![:print:]]*) echo "Wi-Fi values may not contain control characters" >&2; exit 2;; esac
pass_bytes=$(printf '%s' "$PASS" | wc -c | tr -d ' ')
[ "$pass_bytes" -le 63 ] || { echo "Wi-Fi password must be at most 63 bytes" >&2; exit 2; }
[ "$pass_bytes" -eq 0 ] || [ "$pass_bytes" -ge 8 ] || { echo "WPA Wi-Fi password must be at least 8 bytes" >&2; exit 2; }
SSID_HEX=$(printf '%s' "$SSID" | od -An -tx1 | tr -d ' \n' | tr 'A-F' 'a-f')
if [ "$DEST" = / ]; then
    VARLIB=/var/lib/connman
    PERSIST=/mnt/config/setup
else
    VARLIB="$DEST/var/lib/connman"
    PERSIST="$DEST/mnt/config/setup"
fi
mkdir -p "$VARLIB" "$PERSIST"
tmp="$VARLIB/steamlinkhome.config.$$"
{
    printf '[global]\nName = SteamLinkHome\n\n'
    printf '[service_steamlinkhome]\nType = wifi\nSSID = %s\n' "$SSID_HEX"
    if [ -n "$PASS" ]; then printf 'Security = psk\nPassphrase = %s\n' "$PASS"; else printf 'Security = none\n'; fi
    printf 'IPv4 = dhcp\nIPv6 = off\n'
} >"$tmp"
chmod 600 "$tmp" 2>/dev/null || true
mv "$tmp" "$VARLIB/steamlinkhome.config"
cp "$VARLIB/steamlinkhome.config" "$PERSIST/steamlinkhome.config"
chmod 600 "$PERSIST/steamlinkhome.config" 2>/dev/null || true
if [ "$DEST" = / ] && command -v connmanctl >/dev/null 2>&1; then
    connmanctl scan wifi >/dev/null 2>&1 || true
    if [ -n "$PASS" ]; then
        suffix=managed_psk
    else
        suffix=managed_none
    fi
    svc=$(connmanctl services 2>/dev/null | sed -n "s/.*\(wifi_[0-9a-f]*_${SSID_HEX}_${suffix}\).*/\1/p" | head -n 1)
    [ -z "$svc" ] || connmanctl connect "$svc" >/dev/null 2>&1 || true
fi
