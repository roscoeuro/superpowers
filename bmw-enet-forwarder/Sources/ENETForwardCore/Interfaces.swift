import Foundation

/// A single IPv4 interface address on this Mac.
public struct NetInterface: Identifiable {
    public let name: String
    public let ipv4: String
    public var isLinkLocal: Bool { ipv4.hasPrefix("169.254.") }
    public var id: String { "\(name)-\(ipv4)" }
}

/// Enumerates the Mac's up IPv4 interfaces. This is the macOS equivalent of the
/// `iphlpapi.dll` calls the Windows tool uses to find the ENET adapter.
public enum Interfaces {
    public static func list() -> [NetInterface] {
        var results: [NetInterface] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return results }
        defer { freeifaddrs(head) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(bitPattern: cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                 &host, socklen_t(host.count),
                                 nil, 0, NI_NUMERICHOST)
            guard rc == 0 else { continue }
            results.append(NetInterface(name: name, ipv4: String(cString: host)))
        }
        return results
    }

    /// Interfaces most likely to be the ENET cable: link-local IPv4 (169.254/16),
    /// which is what a BMW ZGW assigns over a direct ENET connection.
    public static func likelyEnetInterfaces() -> [NetInterface] {
        list().filter { $0.isLinkLocal }
    }
}
