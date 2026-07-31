# enetforward — native macOS BMW ENET/DoIP forwarder

A small, dependency-free native macOS tool that makes **remote BMW coding work
Mac-to-Windows**, the same way the Windows `forward.exe` does Windows-to-Windows.

The Mac is the machine **at the car** (OBD → ENET → USB/Thunderbolt Ethernet).
It relays the car's diagnostic ports over a VPN so a **remote Windows machine
running E-SYS / ISTA** can code the car as if it were plugged in locally.

Supports **all ENET vehicles**:

| Profile | Cars | Ports forwarded |
|---------|------|-----------------|
| `f`   | F-series (classic ENET) | TCP **6801**, UDP **6811** |
| `g`   | G-series and newer (DoIP / ISO 13400) | TCP **13400**, UDP **13400** |
| `all` | everything (default) | all of the above at once |

The forwarder is **byte-transparent** — it never parses or modifies the
diagnostic protocol, it just pipes the ports through. That's why one tool covers
both classic ENET and DoIP.

---

## Why this works (and why iOS can't)

For F-series, EDIABAS/E-SYS lets you set a **fixed ENET RemoteHost IP**, and DoIP
likewise connects to a host on 13400. So the remote E-SYS never needs to
"discover" the car by broadcast — it connects straight to this Mac's VPN IP, and
this tool relays that to the car. No fake announcements, no kernel extensions.

> **iOS note:** an iPhone/iPad **cannot** be the car-side machine — iOS gives
> apps no access to a USB-Ethernet ENET adapter or link-local routing. The
> car-connected end must be a Mac (or PC). iOS could only ever be a remote
> screen, which isn't what does the coding.

---

## Requirements

- macOS 11+
- Xcode Command Line Tools (`xcode-select --install`) — provides `swift`
- A USB-C/Thunderbolt → Ethernet adapter and a BMW **OBD-to-ENET** cable
- A VPN linking this Mac and the remote Windows machine (**Tailscale** recommended)

---

## Build

```bash
cd bmw-enet-forwarder
swift build -c release
# binary at: .build/release/enetforward
```

Optional — install to your PATH:

```bash
cp .build/release/enetforward /usr/local/bin/
```

---

## Use

### 1. Link the two machines with a VPN (easiest: Tailscale)

Install [Tailscale](https://tailscale.com) on **this Mac** and on the **remote
Windows** machine, sign both into the same tailnet, then note this Mac's
Tailscale IP:

```bash
tailscale ip -4      # e.g. 100.101.102.103
```

### 2. Plug in and start the forwarder (on the Mac, at the car)

Connect OBD → ENET → Ethernet adapter → Mac, switch the car's ignition on, then:

```bash
# Auto-detect the car on the ENET interface (find the interface name first):
enetforward --list-interfaces         # look for a 169.254.x.x address (e.g. en7)
enetforward --scan en7                 # forwards all ENET ports (F + G)

# ...or point at the car IP directly:
enetforward --car 169.254.10.20
```

Force a single profile if you want:

```bash
enetforward --car 169.254.10.20 --profile f     # F-series only
enetforward --car 169.254.10.20 --profile g     # G-series / DoIP only
```

### 3. Point E-SYS at this Mac (on the remote Windows machine)

In **E-SYS / EDIABAS ENET** configuration set the connection's **RemoteHost** to
this Mac's **Tailscale IP** from step 1 (ports stay at their ENET/DoIP defaults —
6801 for F, 13400 for G). Connect and code exactly as you would locally.

For EDIABAS this typically means an `EDIABAS.ini`-style ENET entry such as:

```
Interface = ENET
RemoteHost = 100.101.102.103     ; this Mac's Tailscale IP
Port = 6801                       ; F-series diagnostics (13400 for DoIP)
```

---

## Command reference

```
enetforward --car <ip> [options]
enetforward --scan <interface> [options]
enetforward --list-interfaces

  --car <ip>            Car gateway (ZGW) IP on the ENET link
  --scan <interface>    Auto-detect the car on an interface via ARP
  --profile <f|g|all>   Ports to forward (default: all)
  --listen <ip>         Local bind address (default: 0.0.0.0)
  --no-udp              Forward only the TCP diagnostic port(s)
  --list-interfaces     Print this Mac's IPv4 interfaces and exit
  -h, --help            Show help
```

---

## Troubleshooting

- **`--scan` finds nothing:** the ARP table is empty until traffic flows.
  Confirm the ENET cable is seated, ignition is on, then re-run — or read the
  car IP from `--list-interfaces` / your setup and pass `--car`.
- **E-SYS can't connect:** confirm `tailscale ping <mac-ip>` works from Windows,
  and that this tool logged `TCP <port> listening`. Windows Firewall on the
  E-SYS side and idle VPN timeouts are the usual culprits.
- **G-series won't code but F does (or vice-versa):** you likely forced
  `--profile`. Use the default (`all`) or the matching profile.

---

## Scope / legal

Use this only on a vehicle you **own or are authorised to service**. It is a
network relay for standard BMW ENET/DoIP diagnostics — it performs no coding
itself; that is done by E-SYS/ISTA on the remote end.

---

*This is a self-contained subproject. It is unrelated to the Superpowers plugin
that otherwise lives in this repository.*
