import Foundation
import SwiftUI
import AppKit
import ENETForwardCore

/// Bridges the UI-agnostic `ForwarderEngine` to SwiftUI.
@MainActor
final class ForwarderViewModel: ObservableObject {
    @Published var profile: Profile = .all
    @Published var carIP: String = ""
    @Published var interfaces: [NetInterface] = []
    @Published var selectedInterface: String = ""
    @Published var enableUDP: Bool = true
    @Published var isScanning: Bool = false
    @Published var status: EngineStatus = .idle
    @Published var logLines: [String] = []

    private let engine = ForwarderEngine()
    private var pollTimer: Timer?

    init() {
        Log.sink = { [weak self] line in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.logLines.append(line)
                if self.logLines.count > 300 {
                    self.logLines.removeFirst(self.logLines.count - 300)
                }
            }
        }
        refreshInterfaces()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.status = self.engine.snapshot()
            }
        }
    }

    var isRunning: Bool { status.isRunning }

    /// Best guess at the address the remote E-SYS should use as RemoteHost:
    /// prefer a Tailscale address (100.64.0.0/10), else any non-link-local IP.
    var suggestedRemoteHost: String? {
        if let ts = interfaces.first(where: { $0.ipv4.hasPrefix("100.") }) { return ts.ipv4 }
        return interfaces.first(where: { !$0.isLinkLocal })?.ipv4
    }

    func refreshInterfaces() {
        interfaces = Interfaces.list()
        if selectedInterface.isEmpty || !interfaces.contains(where: { $0.name == selectedInterface }) {
            selectedInterface = interfaces.first(where: { $0.isLinkLocal })?.name
                ?? interfaces.first?.name
                ?? ""
        }
    }

    func scan() {
        guard !selectedInterface.isEmpty else {
            Log.error("Pick an interface to scan.")
            return
        }
        isScanning = true
        let iface = selectedInterface
        let prof = profile
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = ForwarderEngine.discoverCar(interface: iface, profile: prof)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isScanning = false
                if let found = found {
                    self.carIP = found
                } else {
                    Log.warn("No car found on \(iface). Check the cable/ignition or enter the IP manually.")
                }
            }
        }
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        let ip = carIP.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else {
            Log.error("Enter a car IP or press Scan first.")
            return
        }
        do {
            try engine.start(ForwarderConfig(profile: profile, carIP: ip, enableUDP: enableUDP))
            status = engine.snapshot()
        } catch {
            Log.error(error.localizedDescription)
        }
    }

    func stop() {
        engine.stop()
        status = engine.snapshot()
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
