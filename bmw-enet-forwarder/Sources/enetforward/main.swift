import Foundation

// MARK: - Small helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func printUsage() {
    let text = """
    enetforward — native macOS BMW ENET/DoIP forwarder

    Runs on the Mac that is plugged into the car (OBD -> ENET -> USB/Thunderbolt
    Ethernet). It relays the car's diagnostic ports over your VPN so a remote
    Windows machine running E-SYS / ISTA can code the car as if it were local.

    USAGE:
      enetforward --car <ip> [options]
      enetforward --scan <interface> [options]
      enetforward --list-interfaces

    OPTIONS:
      --car <ip>            Car gateway (ZGW) IP on the ENET link, e.g. 169.254.x.x
      --scan <interface>    Auto-detect the car on an interface (e.g. en7) via ARP
      --profile <f|g|all>   Which ENET ports to forward (default: all)
                              f   = classic ENET  (TCP 6801, UDP 6811)  [F-series]
                              g   = DoIP           (TCP 13400, UDP 13400) [G-series+]
                              all = both of the above
      --listen <ip>         Local bind address (default: 0.0.0.0 = all interfaces,
                              which includes your Tailscale/VPN address)
      --no-udp              Forward only the TCP diagnostic port(s)
      --list-interfaces     Print this Mac's IPv4 interfaces and exit
      -h, --help            Show this help

    TYPICAL REMOTE SETUP (F + G):
      1. Install Tailscale on this Mac and on the remote Windows machine
         (same tailnet). Note this Mac's Tailscale IP (100.x.y.z).
      2. Plug OBD->ENET->Ethernet into the car, ignition on.
      3. Run:  enetforward --scan en7        (or --car 169.254.a.b)
      4. On Windows, in E-SYS/EDIABAS ENET config set the RemoteHost to this
         Mac's Tailscale IP. Connect and code as usual.

    Only use this on a vehicle you own or are authorised to service.
    """
    print(text)
}

// MARK: - Argument parsing

var carIP: String?
var scanInterface: String?
var listenAddr = "0.0.0.0"
var profile: Profile = .all
var enableUDP = true

let rawArgs = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < rawArgs.count {
    let arg = rawArgs[index]
    switch arg {
    case "--car":
        index += 1
        carIP = rawArgs[safe: index]
    case "--scan":
        index += 1
        scanInterface = rawArgs[safe: index]
    case "--listen":
        index += 1
        listenAddr = rawArgs[safe: index] ?? listenAddr
    case "--profile":
        index += 1
        guard let raw = rawArgs[safe: index], let parsed = Profile.parse(raw) else {
            Log.error("Invalid --profile value. Use f, g, or all.")
            exit(2)
        }
        profile = parsed
    case "--no-udp":
        enableUDP = false
    case "--list-interfaces":
        for iface in Interfaces.list() {
            let tag = iface.isLinkLocal ? "  <- likely ENET cable" : ""
            print("  \(iface.name)\t\(iface.ipv4)\(tag)")
        }
        exit(0)
    case "-h", "--help":
        printUsage()
        exit(0)
    default:
        Log.error("Unknown argument: \(arg)")
        printUsage()
        exit(2)
    }
    index += 1
}

// MARK: - Resolve the car IP

let tcpPortsForProfile = profile.ports.filter { $0.proto == .tcp }.map { $0.port }

if carIP == nil, let iface = scanInterface {
    Log.info("Scanning \(iface) for the car...")
    carIP = Discovery.findCar(interface: iface, tcpPorts: tcpPortsForProfile)
}

guard let resolvedCarIP = carIP else {
    Log.error("No car IP. Pass --car <ip>, or --scan <interface> once the ENET cable is connected.")
    Log.info("Tip: run `enetforward --list-interfaces` to find the ENET adapter (169.254.x.x).")
    exit(1)
}

// MARK: - Start relays

Log.info("BMW ENET forwarder starting")
Log.info("Profile: \(profile.rawValue)   Car: \(resolvedCarIP)   Bind: \(listenAddr)")

var startedAny = false
for relay in profile.ports {
    if relay.proto == .udp && !enableUDP { continue }
    do {
        switch relay.proto {
        case .tcp:
            try TCPProxy(bind: listenAddr, listenPort: relay.port,
                         carHost: resolvedCarIP, carPort: relay.port,
                         label: relay.label).start()
        case .udp:
            try UDPRelay(bind: listenAddr, listenPort: relay.port,
                         carHost: resolvedCarIP, carPort: relay.port,
                         label: relay.label).start()
        }
        startedAny = true
    } catch {
        Log.error("Could not open \(relay.proto.rawValue) \(relay.port) (\(relay.label)): \(error)")
    }
}

guard startedAny else {
    Log.error("No relays could be started. Is another forwarder already running?")
    exit(1)
}

Log.info("Ready. Point the remote E-SYS RemoteHost at this Mac's VPN IP. Ctrl-C to stop.")
dispatchMain()
