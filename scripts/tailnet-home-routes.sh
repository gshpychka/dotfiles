#!/bin/sh
# Runs on the GL.iNet travel router (OpenWrt), which is not managed by this flake.
#
# Home LAN stays reachable through the tailnet while the router repeats a
# network that uses the same addresses.
#
# gl_tailscale adds "to <upstream-subnet> lookup main" at priority 0, and no
# later rule can preempt a priority 0 rule. Two /25s in main are more specific
# than the upstream's connected /24, so that forced lookup still resolves to
# the tunnel. A single /24 would tie with the connected route, not beat it.
#
# Upstream gateways are the exception: with the whole range diverted they have
# to stay on the local link, or the WAN default route has no next hop.
#
# RANGES covers my.lan.cidr (modules/common/hosts.nix) and must follow it.
#
# Deployment lives in scripts/mudi-runbook.md.

RANGES="192.168.1.0/25 192.168.1.128/25"
TS=tailscale0
STATE=/tmp/tailnet-home-routes.gw

[ -d "/sys/class/net/$TS" ] || exit 0

# withdraw exemptions belonging to a previous upstream
if [ -f "$STATE" ]; then
    while read -r old; do
        [ -n "$old" ] && ip route del "$old/32" 2>/dev/null
    done < "$STATE"
    rm -f "$STATE"
fi

# the default route can lag ifup by a moment
i=0
while [ "$i" -lt 5 ] && [ -z "$(ip route show table main default)" ]; do
    i=$((i + 1))
    sleep 1
done

# exempt every upstream gateway inside the range, before diverting anything
ip route show table main default | awk '
    {
        gw = ""; dev = ""
        for (i = 1; i <= NF; i++) {
            if ($i == "via") gw = $(i + 1)
            if ($i == "dev") dev = $(i + 1)
        }
        if (gw != "" && dev != "") print gw, dev
    }
' | while read -r gw dev; do
    case "$gw" in
        192.168.1.*)
            ip route replace "$gw/32" dev "$dev" scope link
            echo "$gw" >> "$STATE"
            ;;
    esac
done

for r in $RANGES; do
    ip route replace "$r" dev "$TS"
done
