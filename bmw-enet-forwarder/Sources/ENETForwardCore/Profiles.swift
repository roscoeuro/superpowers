import Foundation

/// A port that should be relayed to the car.
public struct RelayPort {
    public let port: UInt16
    public let proto: Proto
    public let label: String

    public enum Proto: String {
        case tcp
        case udp
    }
}

/// Named BMW ENET port profiles. The forwarder is byte-transparent, so a
/// "profile" is simply the set of ports it opens and relays to the car.
public enum Profile: String, CaseIterable {
    /// Classic ENET, used by F-series (and most E/G with the DCAN/ENET era tools).
    /// Diagnostics on TCP 6801, control/announcement on UDP 6811.
    case f

    /// DoIP (ISO 13400), used by G-series and newer. Diagnostics on TCP 13400,
    /// vehicle identification/announcement on UDP 13400.
    case g

    /// Everything above at once — covers F, G and any ENET vehicle.
    case all

    public static func parse(_ raw: String) -> Profile? {
        switch raw.lowercased() {
        case "f", "f-series", "enet", "classic": return .f
        case "g", "g-series", "doip", "new": return .g
        case "all", "both", "*": return .all
        default: return nil
        }
    }

    /// Human label for pickers.
    public var displayName: String {
        switch self {
        case .f: return "F-series (classic ENET)"
        case .g: return "G-series+ (DoIP)"
        case .all: return "All ENET (F + G)"
        }
    }

    public var ports: [RelayPort] {
        switch self {
        case .f:
            return [
                RelayPort(port: 6801, proto: .tcp, label: "ENET diag"),
                RelayPort(port: 6811, proto: .udp, label: "ENET control"),
            ]
        case .g:
            return [
                RelayPort(port: 13400, proto: .tcp, label: "DoIP diag"),
                RelayPort(port: 13400, proto: .udp, label: "DoIP announce"),
            ]
        case .all:
            return Profile.f.ports + Profile.g.ports
        }
    }
}
