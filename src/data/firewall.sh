#!/bin/sh
# Ensure the CZ-QUAKE3 iptables chain exists with the expected rules and is
# jumped to from INPUT. Idempotent: does nothing when everything is in place.
# The appliance rebuilds its firewall on reboots and config changes, which
# removes rules it didn't create; a timer runs this every 30 s to put them back.
BASE=/opt/customization/data
CHAIN=CZ-QUAKE3
# shellcheck source-path=SCRIPTDIR source=quake3.conf
. "$BASE/quake3.conf"

command -v iptables >/dev/null 2>&1 || exit 0
repaired=""

want=0
for _net in $Q3_ALLOW_FROM; do want=$((want + 1)); done
have=$(iptables -S "$CHAIN" 2>/dev/null | grep -c -- "--dport $WEB_PORT -j ACCEPT")
if [ "$have" -ne "$want" ]; then
    iptables -N "$CHAIN" 2>/dev/null || iptables -F "$CHAIN"
    for net in $Q3_ALLOW_FROM; do
        iptables -A "$CHAIN" -s "$net" -p tcp --dport "$WEB_PORT" -j ACCEPT
    done
    repaired=1
fi

if ! iptables -C INPUT -j "$CHAIN" 2>/dev/null; then
    iptables -I INPUT 1 -j "$CHAIN"
    repaired=1
fi

if [ -n "$repaired" ]; then
    logger -t cz-quake3 "firewall: (re)applied tcp/$WEB_PORT from $Q3_ALLOW_FROM"
fi
exit 0
