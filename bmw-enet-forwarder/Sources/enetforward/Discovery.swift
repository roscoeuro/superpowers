import Foundation

/// Best-effort discovery of the car's gateway (ZGW) IP on the ENET link.
///
/// On a direct ENET cable the link is effectively point-to-point, so the ARP
/// neighbour table for that interface contains the car once any traffic has
/// flowed. We list those neighbours and TCP-probe the ENET/DoIP diagnostic
/// ports to confirm which one is the car.
enum Discovery {
    /// TCP connect probe with a timeout, using non-blocking POSIX sockets.
    static func tcpProbe(host: String, port: UInt16, timeoutSeconds: Int32 = 1) -> Bool {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else { return false }
        defer { freeaddrinfo(res) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let rc = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if rc == 0 { return true }
        if errno != EINPROGRESS { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, timeoutSeconds * 1000)
        if ready <= 0 { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 else { return false }
        return soError == 0
    }

    /// Reads the ARP neighbour table for an interface (`arp -an -i <iface>`).
    static func neighbours(interface: String) -> [String] {
        let output = shell("/usr/sbin/arp", ["-an", "-i", interface])
        var ips: [String] = []
        for line in output.split(separator: "\n") {
            // e.g. "? (169.254.1.20) at aa:bb:cc:dd:ee:ff on en7 ifscope [ethernet]"
            guard let open = line.firstIndex(of: "("),
                  let close = line.firstIndex(of: ")"),
                  open < close else { continue }
            let ip = String(line[line.index(after: open)..<close])
            if ip.contains(".") && !ip.contains("incomplete") {
                ips.append(ip)
            }
        }
        return ips
    }

    /// Scan an interface for a host answering on any of the given diagnostic
    /// TCP ports. Returns the first matching IP, if any.
    static func findCar(interface: String, tcpPorts: [UInt16]) -> String? {
        let candidates = neighbours(interface: interface)
        if candidates.isEmpty {
            Log.warn("No ARP neighbours on \(interface) yet. Connect the ENET cable, turn the car's ignition on, then retry — or pass --car <ip>.")
            return nil
        }
        Log.info("Probing \(candidates.count) neighbour(s) on \(interface): \(candidates.joined(separator: ", "))")
        for ip in candidates {
            for port in tcpPorts where tcpProbe(host: ip, port: port) {
                Log.info("Car found: \(ip) answers on TCP \(port)")
                return ip
            }
        }
        return nil
    }
}

/// Runs a command and returns its stdout as a string. Used only for `arp`.
func shell(_ launchPath: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    } catch {
        Log.warn("Failed to run \(launchPath): \(error)")
        return ""
    }
}
