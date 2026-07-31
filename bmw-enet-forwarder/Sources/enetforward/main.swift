import Foundation
import ENETForwardCore

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

    A menu-bar app (enetforwardapp) is also available for click-to-run use.

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

if carIP == nil, let iface = scanInterface {
    Log.info("Scanning \(iface) for the car...")
    carIP = ForwarderEngine.discoverCar(interface: iface, profile: profile)
}

guard let resolvedCarIP = carIP else {
    Log.error("No car IP. Pass --car <ip>, or --scan <interface> once the ENET cable is connected.")
    Log.info("Tip: run `enetforward --list-interfaces` to find the ENET adapter (169.254.x.x).")
    exit(1)
}

// MARK: - Start

Log.info("BMW ENET forwarder starting")
Log.info("Profile: \(profile.rawValue)   Car: \(resolvedCarIP)   Bind: \(listenAddr)")

let engine = ForwarderEngine()
do {
    try engine.start(ForwarderConfig(profile: profile, carIP: resolvedCarIP,
                                     listenAddr: listenAddr, enableUDP: enableUDP))
} catch {
    Log.error("\(error.localizedDescription)")
    exit(1)
}

for line in engine.snapshot().listeners {
    Log.info("Listening: \(line)")
}
Log.info("Ready. Point the remote E-SYS RemoteHost at this Mac's VPN IP. Ctrl-C to stop.")

// Stop cleanly on SIGINT/SIGTERM.
let signalQueue = DispatchQueue(label: "signals")
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
    source.setEventHandler {
        Log.info("Shutting down...")
        engine.stop()
        exit(0)
    }
    source.resume()
    // Keep the source alive for the process lifetime.
    signalSources.append(source)
}

dispatchMain()
