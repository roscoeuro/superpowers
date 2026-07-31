import SwiftUI
import AppKit
import ENETForwardCore

struct MenuContentView: View {
    @ObservedObject var vm: ForwarderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            configSection
            Divider()
            statusSection
            Divider()
            logSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: vm.isRunning ? "antenna.radiowaves.left.and.right" : "car")
                .foregroundColor(vm.isRunning ? .green : .secondary)
            Text("BMW ENET Forwarder")
                .font(.headline)
            Spacer()
            Circle()
                .fill(vm.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
        }
    }

    // MARK: Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Cars", selection: $vm.profile) {
                ForEach(Profile.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .disabled(vm.isRunning)

            HStack(spacing: 6) {
                Picker("Interface", selection: $vm.selectedInterface) {
                    ForEach(vm.interfaces) { iface in
                        Text("\(iface.name) (\(iface.ipv4))\(iface.isLinkLocal ? " •" : "")")
                            .tag(iface.name)
                    }
                }
                .disabled(vm.isRunning)
                Button {
                    vm.refreshInterfaces()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh interfaces")
                .disabled(vm.isRunning)
            }

            HStack(spacing: 6) {
                TextField("Car IP (169.254.x.x)", text: $vm.carIP)
                    .textFieldStyle(.roundedBorder)
                    .disabled(vm.isRunning)
                Button(vm.isScanning ? "Scanning…" : "Scan") {
                    vm.scan()
                }
                .disabled(vm.isRunning || vm.isScanning || vm.selectedInterface.isEmpty)
            }

            Toggle("Forward control/announce (UDP)", isOn: $vm.enableUDP)
                .disabled(vm.isRunning)
                .font(.caption)
        }
    }

    // MARK: Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.isRunning {
                Label("Forwarding \(vm.status.profile.displayName) → \(vm.status.carIP)",
                      systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                ForEach(vm.status.listeners, id: \.self) { line in
                    Text("• \(line)").font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text("Active sessions: \(vm.status.activeConnections)   ·   Total: \(vm.status.totalConnections)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Stopped").font(.caption).foregroundColor(.secondary)
            }

            if let host = vm.suggestedRemoteHost {
                HStack(spacing: 6) {
                    Text("E-SYS RemoteHost:").font(.caption2).foregroundColor(.secondary)
                    Text(host).font(.system(.caption2, design: .monospaced))
                    Button {
                        vm.copyToPasteboard(host)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy this Mac's VPN IP for E-SYS")
                }
            }

            if let error = vm.status.lastError {
                Text(error).font(.caption2).foregroundColor(.red)
            }
        }
    }

    // MARK: Log

    private var logSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(vm.logLines.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(item.offset)
                    }
                }
            }
            .frame(height: 90)
            .onChange(of: vm.logLines.count) { _ in
                if let last = vm.logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button(vm.isRunning ? "Stop" : "Start") {
                vm.toggle()
            }
            .keyboardShortcut(.defaultAction)
            .tint(vm.isRunning ? .red : .green)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
