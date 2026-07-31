import Foundation

/// Configuration for a forwarding session.
public struct ForwarderConfig {
    public var profile: Profile
    public var carIP: String
    public var listenAddr: String
    public var enableUDP: Bool

    public init(profile: Profile, carIP: String, listenAddr: String = "0.0.0.0", enableUDP: Bool = true) {
        self.profile = profile
        self.carIP = carIP
        self.listenAddr = listenAddr
        self.enableUDP = enableUDP
    }
}

/// A point-in-time snapshot of the engine, safe to read from the UI.
public struct EngineStatus {
    public var isRunning: Bool
    public var carIP: String
    public var profile: Profile
    public var listeners: [String]
    public var activeConnections: Int
    public var totalConnections: Int
    public var lastError: String?

    public static let idle = EngineStatus(
        isRunning: false, carIP: "", profile: .all,
        listeners: [], activeConnections: 0, totalConnections: 0, lastError: nil
    )
}

/// Orchestrates the TCP/UDP relays for a profile. Shared by the CLI and the
/// menu-bar app so both drive identical behaviour.
public final class ForwarderEngine {
    private var tcpProxies: [TCPProxy] = []
    private var udpRelays: [UDPRelay] = []
    private let stats = Stats()
    private var config: ForwarderConfig?
    private var listenerLabels: [String] = []
    private var lastError: String?
    private let lock = NSLock()

    public init() {}

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return config != nil
    }

    /// TCP ports for a profile, used by discovery to confirm the car.
    public static func tcpPorts(for profile: Profile) -> [UInt16] {
        profile.ports.filter { $0.proto == .tcp }.map { $0.port }
    }

    /// Blocking best-effort discovery of the car IP on an interface.
    public static func discoverCar(interface: String, profile: Profile) -> String? {
        Discovery.findCar(interface: interface, tcpPorts: tcpPorts(for: profile))
    }

    public func start(_ config: ForwarderConfig) throws {
        lock.lock()
        guard self.config == nil else {
            lock.unlock()
            throw ForwarderError.alreadyRunning
        }
        lock.unlock()

        var startedTCP: [TCPProxy] = []
        var startedUDP: [UDPRelay] = []
        var labels: [String] = []

        for relay in config.profile.ports {
            if relay.proto == .udp && !config.enableUDP { continue }
            do {
                switch relay.proto {
                case .tcp:
                    let proxy = TCPProxy(bind: config.listenAddr, listenPort: relay.port,
                                         carHost: config.carIP, carPort: relay.port,
                                         label: relay.label, stats: stats)
                    try proxy.start()
                    startedTCP.append(proxy)
                    labels.append("TCP \(relay.port) — \(relay.label)")
                case .udp:
                    let udp = UDPRelay(bind: config.listenAddr, listenPort: relay.port,
                                       carHost: config.carIP, carPort: relay.port,
                                       label: relay.label)
                    try udp.start()
                    startedUDP.append(udp)
                    labels.append("UDP \(relay.port) — \(relay.label)")
                }
            } catch {
                // Roll back anything already started so we don't leak listeners.
                startedTCP.forEach { $0.stop() }
                startedUDP.forEach { $0.stop() }
                let message = "Could not open \(relay.proto.rawValue) \(relay.port): \(error)"
                lock.lock(); lastError = message; lock.unlock()
                throw ForwarderError.listenerFailed(message)
            }
        }

        guard !labels.isEmpty else {
            throw ForwarderError.nothingToStart
        }

        lock.lock()
        tcpProxies = startedTCP
        udpRelays = startedUDP
        listenerLabels = labels
        self.config = config
        lastError = nil
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let tcp = tcpProxies
        let udp = udpRelays
        tcpProxies = []
        udpRelays = []
        listenerLabels = []
        config = nil
        lock.unlock()

        tcp.forEach { $0.stop() }
        udp.forEach { $0.stop() }
        Log.info("Forwarder stopped")
    }

    public func snapshot() -> EngineStatus {
        lock.lock()
        let cfg = config
        let labels = listenerLabels
        let err = lastError
        lock.unlock()

        return EngineStatus(
            isRunning: cfg != nil,
            carIP: cfg?.carIP ?? "",
            profile: cfg?.profile ?? .all,
            listeners: labels,
            activeConnections: stats.activeConnections,
            totalConnections: stats.totalConnections,
            lastError: err
        )
    }
}

public enum ForwarderError: LocalizedError {
    case alreadyRunning
    case nothingToStart
    case listenerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Forwarder is already running."
        case .nothingToStart: return "No relays could be started."
        case .listenerFailed(let message): return message
        }
    }
}
