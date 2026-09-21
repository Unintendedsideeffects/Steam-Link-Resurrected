#!/bin/ash
#
# WiFi uplink watchdog.
#
# For a box whose uplink is WiFi, eth0 is no longer a management path: if the
# WiFi link dies the device is simply gone until someone walks to it. This
# escalates through progressively heavier recovery steps and LOGS every
# transition, so the underlying failure stays diagnosable instead of being
# silently papered over. Read the log before concluding "it recovers fine" --
# if it is climbing to level 3 regularly, something real is wrong and wants
# fixing at the source, not here.
#
# Everything device-specific is derived at runtime from ConnMan and the
# routing table, so this file carries no addresses or SSIDs. Override any of
# it in /mnt/config/setup/setup.conf with WIFI_WATCHDOG_SVC / _UP / _GW.

CONF=/mnt/config/setup/setup.conf
LOG=/mnt/config/log/wifi-watchdog.log
STATE=/mnt/config/log/wifi-watchdog.state
PIDFILE=/var/run/wifi-watchdog.pid
REBOOT_STAMP=/mnt/config/log/wifi-watchdog.lastreboot

INTERVAL=15
# consecutive failed checks before each escalation rung (x15s)
L1_AT=4     # 1 min  - ask connman to reconnect
L2_AT=8     # 2 min  - restart connmand
L3_AT=14    # 3.5min - reload the whole wifi stack
L4_AT=24    # 6 min  - reboot (rate limited)

# single instance
if [ -f $PIDFILE ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then exit 0; fi

mkdir -p /mnt/config/log /var/run
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> $LOG; }
getconf_() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n1 | tr -d '\r'; }

# The favourite/autoconnect wifi service ConnMan is managing.
detect_svc() { connmanctl services 2>/dev/null | awk '{print $NF}' | grep '^wifi_' | head -1; }
# The interface and gateway currently carrying the default route.
detect_up()  { route -n 2>/dev/null | awk '$1=="0.0.0.0" {print $8; exit}'; }
detect_gw()  { route -n 2>/dev/null | awk '$1=="0.0.0.0" {print $2; exit}'; }
iface_ip()   { ifconfig "$1" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p'; }

SVC=$(getconf_ WIFI_WATCHDOG_SVC); [ -n "$SVC" ] || SVC=$(detect_svc)
UP=$(getconf_ WIFI_WATCHDOG_UP);   [ -n "$UP" ]  || UP=$(detect_up)
GW=$(getconf_ WIFI_WATCHDOG_GW);   [ -n "$GW" ]  || GW=$(detect_gw)

# Without a wifi service this box is not WiFi-uplinked; stay inert rather than
# guessing, or the escalation ladder would eventually reboot a healthy device.
[ -n "$SVC" ] || exit 0
case "$UP" in mlan0|wlan0|wlp*) ;; *) exit 0 ;; esac
[ -n "$GW" ] || exit 0

diag() {
	ap=$(iwconfig $UP 2>/dev/null | sed -n 's/.*Access Point: *//p' | tr -d ' ')
	ip=$(iface_ip $UP)
	st=$(connmanctl services $SVC 2>/dev/null | sed -n 's/.*State *= *//p')
	echo "ap=${ap:-none} ip=${ip:-none} connman=${st:-unknown}"
}

healthy() {
	# Any address on the uplink, not a pinned one: a DHCP change is not an outage.
	[ -n "$(iface_ip $UP)" ] || return 1
	# two chances: a single lost frame on wifi is not an outage
	ping -c1 -W2 $GW >/dev/null 2>&1 && return 0
	ping -c1 -W2 $GW >/dev/null 2>&1 && return 0
	return 1
}

recover_l1() {
	log "L1: asking connman to reconnect"
	connmanctl connect $SVC >/dev/null 2>&1
}

recover_l2() {
	log "L2: restarting connmand (supervisor loop restarts it)"
	killall connmand 2>/dev/null
}

recover_l3() {
	log "L3: full wifi stack reload (rmmod + wifi_reset + sdio rescan)"
	killall wpa_supplicant 2>/dev/null
	rmmod sd8897 2>/dev/null
	rmmod 8897mlan 2>/dev/null
	/bin/wifi_reset 2>/dev/null
	echo 1 > /sys/devices/soc.0/f7ab0000.sdhci/mmc_host/mmc0/rescan 2>/dev/null
	sleep 3
	/etc/init.d/start_wifi.sh >/dev/null 2>&1
	sleep 3
	/etc/init.d/wpa_supplicant.sh >/dev/null 2>&1 &
	sleep 2
	killall connmand 2>/dev/null
	sleep 10
	connmanctl connect $SVC >/dev/null 2>&1
}

recover_l4() {
	now=$(date +%s)
	last=0
	[ -f $REBOOT_STAMP ] && last=$(cat $REBOOT_STAMP 2>/dev/null)
	[ -z "$last" ] && last=0
	if [ $((now - last)) -lt 3600 ]; then
		log "L4: reboot suppressed, last watchdog reboot was $((now - last))s ago"
		return
	fi
	log "L4: rebooting as last resort -- $(diag)"
	echo $now > $REBOOT_STAMP
	sync
	/etc/init.d/reboot.sh
}

(
echo $$ > $PIDFILE
log "watchdog started (interval ${INTERVAL}s, uplink=$UP gw=$GW)"
fails=0
while true; do
	if healthy; then
		if [ $fails -gt 0 ]; then
			log "RECOVERED after $fails failed checks -- $(diag)"
		fi
		fails=0
		echo "ok $(date '+%Y-%m-%d %H:%M:%S')" > $STATE
	else
		fails=$((fails+1))
		log "unhealthy (check $fails) -- $(diag)"
		echo "FAILING since $fails checks $(date '+%Y-%m-%d %H:%M:%S')" > $STATE
		case $fails in
			$L1_AT) recover_l1 ;;
			$L2_AT) recover_l2 ;;
			$L3_AT) recover_l3 ;;
			$L4_AT) recover_l4 ;;
		esac
	fi
	sleep $INTERVAL
done
) </dev/null >/dev/null 2>&1 &
