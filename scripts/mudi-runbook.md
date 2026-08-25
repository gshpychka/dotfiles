# Mudi runbook

GL.iNet Mudi (GL-E5800), firmware 4.10. Fresh device to current state.
Router LAN is 192.168.8.0/24, harbor is the DNS server and exit node.

Never bind `tailscale0` to a netifd interface: netifd flushes the addresses of
a device it claims, which drops the tailnet.

## 1. Console, not scriptable

- GL UI > Applications > Tailscale: enable, open the device link, log in.
- Admin console > this node > route settings: approve `192.168.8.0/24` and
  `192.168.100.1/32`, disable key expiry.
- Admin console > policy: add an `ssh` section, otherwise tailscaled refuses
  `ssh oasis` even though dropbear is listening.

## 2. From eve

The router has no sftp-server, so scp does not work.

```sh
ssh root@192.168.8.1 'cat > /etc/tailnet-home-routes.sh; chmod +x /etc/tailnet-home-routes.sh' \
  < scripts/tailnet-home-routes.sh
```

## 3. On the router

```sh
# DNS: dnsmasq forwards to harbor, and the router resolves through dnsmasq
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].server='192.168.1.2'
uci set dhcp.@dnsmasq[0].localuse='1'           # unset, the router queries carrier DNS that the exit node cannot reach
uci set dhcp.@dnsmasq[0].domainneeded='0'       # forward dotless names to harbor
uci set dhcp.@dnsmasq[0].rebind_protection='0'  # harbor answers with RFC1918 addresses
uci commit dhcp

# exit node and advertised routes
uci set tailscale.settings.exit_node_ip='100.113.82.84'   # harbor
uci -q delete tailscale.settings.extra_set_args
uci add_list tailscale.settings.extra_set_args='--advertise-routes=192.168.8.0/24,192.168.100.1/32'
uci commit tailscale   # a list: gl_tailscale reads extra_set_args_LENGTH and skips a plain option

# LAN clients egress through the exit node
uci set firewall.tailscale0.masq='1'
uci commit firewall

# LAN traffic that misses the tunnel is dropped rather than leaked
uci set network.ts_block_lan_leak=rule
uci set network.ts_block_lan_leak.in='lan'
uci set network.ts_block_lan_leak.priority='5280'
uci set network.ts_block_lan_leak.action='blackhole'

# Starlink dish in bypass mode, from the LAN and from the tailnet
uci set network.starlink=route
uci set network.starlink.interface='wan'
uci set network.starlink.target='192.168.100.1/32'
uci set network.starlink_rule=rule
uci set network.starlink_rule.dest='192.168.100.1/32'
uci set network.starlink_rule.lookup='254'
uci set network.starlink_rule.priority='1000'
uci commit network
uci set firewall.starlink_tailscale=rule
uci set firewall.starlink_tailscale.name='Starlink Tailscale'
uci set firewall.starlink_tailscale.family='ipv4'
uci set firewall.starlink_tailscale.src='tailscale0'
uci set firewall.starlink_tailscale.dest='wan'
uci set firewall.starlink_tailscale.dest_ip='192.168.100.1'
uci set firewall.starlink_tailscale.proto='all'
uci set firewall.starlink_tailscale.target='ACCEPT'
uci commit firewall

# home LAN stays reachable when the repeated network is also 192.168.1.0/24
printf '%s\n' '[ "$DEVICENAME" = "tailscale0" ] && [ "$ACTION" = "add" ] && sh /etc/tailnet-home-routes.sh' \
  > /etc/hotplug.d/net/99-tailnet-home-routes
printf '%s\n' '[ "$ACTION" = "ifup" ] && sh /etc/tailnet-home-routes.sh' \
  > /etc/hotplug.d/iface/99-tailnet-home-routes

# /etc/hotplug.d is outside the sysupgrade keep list, and sysupgrade.conf is
# not kept either, so it lists itself
printf '%s\n' /etc/sysupgrade.conf /etc/tailnet-home-routes.sh \
  /etc/hotplug.d/net/99-tailnet-home-routes /etc/hotplug.d/iface/99-tailnet-home-routes \
  >> /etc/sysupgrade.conf

/etc/init.d/network reload
/etc/init.d/dnsmasq restart
/usr/bin/gl_tailscale restart
```

## 4. Touchscreen wallpaper

`gl_screen` reads `/etc/gl_screen/image/*.png` at runtime. Needs a 240x320 and a
480x640 PNG, both 8-bit RGBA; the script keeps `*.orig` backups and registers
all four paths in `/etc/sysupgrade.conf`.

```sh
scripts/mudi-wallpaper.sh <240x320.png> <480x640.png>
```

## 5. Check

```sh
tailscale status | head -3                   # harbor active, exit node
curl -4 -s https://ifconfig.co               # home WAN address
cat /tmp/resolv.conf                         # nameserver 127.0.0.1
nslookup hoard.glib.sh                       # 192.168.1.3
nslookup hoard                               # dotless name reaches harbor
ip route show table main | grep 192.168.1    # two /25s via tailscale0
sysupgrade -l | grep tailnet                 # both hooks and the script
```

On a repeated 192.168.1.0/24 network, `ip route get 192.168.1.2` is
`dev tailscale0` and `ip route get <upstream gateway>` stays on the upstream
device, with that gateway recorded in `/tmp/tailnet-home-routes.gw`.
