#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec "$ROOT/scripts/create-key.sh" "$@"
