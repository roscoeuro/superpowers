import Foundation
import Network

/// Transparent UDP relay for the ENET control port (6811) and DoIP
/// announcement/identification port (13400). Each remote source is delivered by
/// NWListener as its own "connection"; we pair it with a fresh datagram socket
/// to the car and shuttle datagrams both ways, preserving message boundaries.
final class UDPRelay {
    private let bindHost: NWEndpoint.Host?
    private let listenPort: NWEndpoint.Port
    private let carHost: NWEndpoint.Host
    private let carPort: NWEndpoint.Port
    private let label: String
    private let queue: DispatchQueue
    private var listener: NWListener?

    init(bind: String, listenPort: UInt16, carHost: String, carPort: UInt16, label: String) {
        self.bindHost = (bind == "0.0.0.0" || bind.isEmpty) ? nil : NWEndpoint.Host(bind)
        self.listenPort = NWEndpoint.Port(rawValue: listenPort)!
        self.carHost = NWEndpoint.Host(carHost)
        self.carPort = NWEndpoint.Port(rawValue: carPort)!
        self.label = label
        self.queue = DispatchQueue(label: "udp.\(listenPort)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func start() throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        if let bindHost = bindHost {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: bindHost, port: listenPort)
        }

        let listener = try NWListener(using: params, on: listenPort)
        self.listener = listener

        listener.stateUpdateHandler = { [label, listenPort] state in
            switch state {
            case .ready:
                Log.info("UDP \(listenPort) (\(label)) listening -> car:\(listenPort)")
            case .failed(let error):
                Log.error("UDP \(listenPort) (\(label)) failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] client in
            self?.accept(client)
        }

        listener.start(queue: queue)
    }

    private func accept(_ client: NWConnection) {
        let upstream = NWConnection(host: carHost, port: carPort, using: .udp)
        UDPSession(client: client, upstream: upstream, label: label, queue: queue).start()
    }
}

private final class UDPSession {
    private let client: NWConnection
    private let upstream: NWConnection
    private let label: String
    private let queue: DispatchQueue
    private var isClosed = false

    init(client: NWConnection, upstream: NWConnection, label: String, queue: DispatchQueue) {
        self.client = client
        self.upstream = upstream
        self.label = label
        self.queue = queue
    }

    func start() {
        upstream.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Log.warn("[\(self?.label ?? "")] udp upstream failed: \(error)")
                self?.close()
            }
        }
        client.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
            if case .cancelled = state { self?.close() }
        }

        client.start(queue: queue)
        upstream.start(queue: queue)

        pumpDatagrams(from: client, to: upstream)
        pumpDatagrams(from: upstream, to: client)
    }

    private func pumpDatagrams(from source: NWConnection, to destination: NWConnection) {
        source.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, !self.isClosed else { return }
            if let data = data, !data.isEmpty {
                destination.send(content: data, completion: .idempotent)
            }
            if error != nil { self.close(); return }
            self.pumpDatagrams(from: source, to: destination)
        }
    }

    private func close() {
        queue.async { [weak self] in
            guard let self = self, !self.isClosed else { return }
            self.isClosed = true
            self.client.cancel()
            self.upstream.cancel()
        }
    }
}
