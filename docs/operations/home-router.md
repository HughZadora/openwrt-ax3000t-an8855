# Xiaomi AX3000T (AN8855) router / Tailscale networking configuration

> **Date**: 2026-08-15
> **Author**: hugh
> **Scope**: OpenWrt configuration and Tailscale networking handover on the
> Xiaomi Mi Router AX3000T (AN8855)
> **Purpose**: record the device's current configuration, network topology, and
> handover points, for later maintenance or handover reference.
> **Status**: effective (corresponds to OpenWrt SNAPSHOT r0-9f3157a)

## Change log

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| 1.0 | 2026-08-15 | hugh | Added the DOC_HEADER block (content matches the original) |

## Project goal

Record the configuration and handover points of the **Xiaomi Mi Router
AX3000T (AN8855 switch)** at `192.168.31.1`, focusing on PPPoE broadband +
single-arm access to the optical modem, Tailscale networking (subnet
advertisement), and office-node interconnection.

## Device and environment

- Model: Xiaomi Mi Router AX3000T (AN8855 5-port gigabit switch)
- System: OpenWrt SNAPSHOT `r0-9f3157a`, architecture `aarch64_cortex-a53`
- Hostname: `OpenWrt`; Tailscale node: `xiaomi-ax3000t`, network IP
  **`100.104.191.81`**
- Login: `ssh root@192.168.31.1` (local LAN)

## Network topology and roles

- LAN: `br-lan` = `192.168.31.1/24` (bridging `lan2/lan3/lan4`, the AN8855
  downstream ports)
- WAN: `wan@eth0`, **PPPoE dial-up** (credentials in `/etc/config/network`),
  `pppoe-wan` receives public `100.77.x`
- Single-arm modem access: a second static `192.168.1.99/24` on the same
  physical WAN port for reaching the optical modem `192.168.1.1`
- Role: home router; also a Tailscale network node, **advertising subnet
  `192.168.31.0/24`**, allowing remote network devices to reach the home LAN
  through it.

## Key configuration

### Network (/etc/config/network)

| Interface | Protocol | Address | Description |
|-----------|----------|---------|-------------|
| `br-lan` | static | `192.168.31.1/24` | LAN, bridging `lan2/lan3/lan4` |
| `wan` | pppoe | dial-up | Upstream PPPoE broadband |
| `Modem` | static | `192.168.1.99/24`, device=`wan` | Single-arm access to the modem `192.168.1.1` (shares the WAN port with PPPoE) |
| `tailscale0` | TUN | `100.104.191.81/32` | Created dynamically by tailscaled, not in the network config |

Key points:
- The `Modem` interface's `device` must be `wan` (DSA downstream port), not
  `eth0` (master CPU port); otherwise ARP fails and pinging the modem fails.
- The `Modem` interface currently has `gateway 192.168.1.1` configured, but in
  practice it **does not steal the default route** (the default route comes
  from PPPoE via `default via 100.77.x dev pppoe-wan`, and internet access
  works normally). If traffic starts going through the modem, remove that
  gateway.

### Tailscale
- Node `xiaomi-ax3000t`, network IP `100.104.191.81`, status: logged in, running
- **Advertised routes**: `192.168.31.0/24` (approved in the console,
  `PrimaryRoutes` effective), `NoSNAT: true` (preserves real source addresses)
- `CorpDNS: false` (**MagicDNS off**; access exclusively by IP)
- `RouteAll: false` (this node does not accept routes advertised by other
  nodes — only the advertiser needs this; enable as needed)
- `RunSSH: false`; starts on boot; state persisted to
  `/etc/tailscale/tailscaled.state`
- Auto-recovery: the init.d script includes `procd respawn`, so tailscaled
  restarts automatically on crash; disconnection reconnection is handled by
  the built-in mechanism

### Firewall (firewall4 / nftables)
- Zones: `lan` (ACCEPT), `wan` (REJECT, masq), `modem` (ACCEPT, masq,
  network=`Modem`), **`tailscale`** (ACCEPT, network=`tailscale`)
- Forwards: `lan→wan`, `lan→modem`, `tailscale→lan`, `lan→tailscale` (the
  latter two implement network ↔ LAN mutual access)
- This device itself being accessed via the network: Tailscale's built-in
  `ts-input` (`iifname "tailscale0*" accept`) allows TCP

## Key configuration 1: single-arm dial-up + modem access

One WAN cable simultaneously PPPoE dials for broadband and accesses the modem
management page:

```sh
# Modem interface (static 192.168.1.99 bound to wan, same physical port as PPPoE)
uci set network.Modem.device='wan'
uci set network.Modem.proto='static'
uci set network.Modem.ipaddr='192.168.1.99'
uci set network.Modem.netmask='255.255.255.0'
uci commit network

# modem zone: allow inbound + masq (so LAN devices accessing the modem appear
# to the modem as source 192.168.1.99)
uci set firewall.@zone[2].name='modem'
uci set firewall.@zone[2].network='Modem'
uci set firewall.@zone[2].input='ACCEPT'
uci set firewall.@zone[2].output='ACCEPT'
uci set firewall.@zone[2].forward='ACCEPT'
uci set firewall.@zone[2].masq='1'
uci add firewall forwarding            # lan -> modem
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='modem'
uci commit firewall
```

Verification: `echo -e "GET / HTTP/1.0\r\n\r" | nc 192.168.1.1 80` should
return `HTTP/1.0 200 OK`.

## Key configuration 2: Tailscale subnet advertisement (remote access to the home LAN)

```sh
# Advertise 192.168.31.0/24, preserve real source addresses, keep MagicDNS off
tailscale up --accept-dns=false --advertise-routes=192.168.31.0/24 --snat-subnet-routes=false

# Create the tailscale zone + forwarding (network ↔ LAN mutual access)
uci set network.tailscale='interface'
uci set network.tailscale.ifname='tailscale0'
uci set network.tailscale.proto='none'
uci commit network

uci add firewall zone
uci set firewall.@zone[-1].name='tailscale'
uci set firewall.@zone[-1].network='tailscale'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci commit firewall

uci add firewall forwarding          # tailscale -> lan
uci set firewall.@forwarding[-1].src='tailscale'
uci set firewall.@forwarding[-1].dest='lan'
uci add firewall forwarding          # lan -> tailscale
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='tailscale'
uci commit firewall
```

**Remote-side requirements:**
1. Subnet route `192.168.31.0/24` approved in the Tailscale console
   (`PrimaryRoutes` effective)
2. Remote clients need **accept-routes** enabled, for example Ubuntu:
   `tailscale up --reset --accept-routes --accept-dns=false --ssh`
3. Once effective, the remote can `ping 192.168.31.x` to directly reach home
   LAN devices (via direct tunnel, roughly 10-70 ms)

## Key configuration 3: system / WiFi basic optimisation

- Time zone: `Asia/Shanghai` (CST-8), NTP using domestic (Alibaba/Tencent)
  sources
- DNS: keep the ISP upstream, do not enable MagicDNS
- WiFi: dual-band unified SSID `ZhuZhu Home`, WPA2/WPA3-PSK; 2.4G channel
  1/HE20, 5G channel 149 (actually 153)/HE80, country=`CN`, Tx 28 dBm
- Default firewall wan zone `input=REJECT`: the public internet cannot access
  ports 80/443/22

## Usage

- Any node in the network accessing this device: `ssh root@100.104.191.81`
- Remote access to home LAN devices: `ssh root@192.168.31.x` or browse
  `192.168.31.x` directly (requires subnet route approval + client
  accept-routes)
- Because MagicDNS is off, always use IP addresses.

## Useful commands (on this device)

```sh
tailscale status                       # network status
tailscale ping 100.104.191.81        # control-plane connectivity
tailscale debug prefs | grep -i corp  # confirm MagicDNS is off
tailscale debug prefs | grep -iA1 AdvertiseRoutes  # confirm advertised subnet
/etc/init.d/tailscale restart
/etc/init.d/firewall reload
```

## Handover points / pitfalls

- **The single-arm modem access IP must be bound to `wan`**, not `eth0`; and
  the `Modem` interface must **not** have a gateway configured (it would steal
  the default route).
- **ICMP blocked ≠ SSH blocked**: SSH works fine but ping shows
  `Destination Port Unreachable` because of the fw4 fallback; the `tailscale0`
  zone or an include script needs to allow input.
- Do **not** enable MagicDNS by changing `CorpDNS` (the requirements specify
  it must be off).
- Subnet advertisement needs **console approval** + **remote accept-routes**;
  both are required.
- WAN disconnection causes no default route, DNS failure, and Tailscale losing
  its control-plane connection (`tailscale status` shows logged out). Ensure
  the WAN has a link first; `procd respawn` ensures tailscaled restarts after
  a crash.
- The **root password** must be set: LAN devices can SSH in directly (the
  public internet is blocked by the wan zone REJECT).

## Office node interconnection

- This device `xiaomi-ax3000t` (100.104.191.81, at home) and the office `dev`
  (100.95.46.79, Ubuntu) are on the same network; `tailscale ping` direct
  connection is about 10 ms.
- The office `dev` has accept-routes enabled; accessing the home `192.168.31.x`
  from the office was tested and works (router 11 ms, LAN Mac 65 ms).

## Known limitations

- Remote access to other devices in the home LAN requires subnet route approval
  plus client accept-routes (verified from this device and the office `dev`).
- Depends on the home network link being up; WAN disconnection means loss of
  external reachability.
