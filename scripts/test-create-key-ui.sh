#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/steamlink-create-key-ui-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
COUNT="$WORK/count"
: >"$COUNT"
UI="$WORK/ui"
printf '%s\n' \
    '#!/bin/sh' \
    'case "$*" in' \
    '    *--inputbox*)' \
    '        n=$(wc -c <"$STEAMLINK_TEST_COUNT")' \
    '        if [ "$n" -eq 0 ]; then printf %s typed-value >&2; else printf %s "" >&2; fi' \
    '        printf x >>"$STEAMLINK_TEST_COUNT"' \
    '        ;;' \
    '    *) exit 0;;' \
    'esac' >"$UI"
chmod 755 "$UI"

export STEAMLINK_TEST_COUNT="$COUNT" UI="$UI"
eval "$(sed -n '8,13p' "$ROOT/scripts/create-key.sh")"
ask 'first' 'default'
test "$REPLY" = typed-value
ask 'second' 'default'
test -z "$REPLY"

echo 'TUI input contract OK'
grep -q 'WEB_SECRET=$(get WEB_SECRET)' "$ROOT/steamlink/overlay/etc/init.d/startup/S04steamlink-setup.sh"
grep -q 'ENABLE_DIAGNOSTICS' "$ROOT/steamlink/overlay/etc/init.d/startup/S04steamlink-setup.sh"
grep -q "tr '+' ' '" "$ROOT/steamlink/overlay/mnt/config/setup/www/cgi-bin/setup.cgi"
