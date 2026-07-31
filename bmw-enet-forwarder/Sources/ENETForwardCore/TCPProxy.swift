import Foundation
import Network

/// Transparent TCP relay: accepts connections from the remote E-SYS machine
/// (over the VPN) and pipes them, byte-for-byte, to the car's gateway.
/// The ENET/DoIP framing is never parsed — it is just forwarded.
final class TCPProxy {
    private let bindHost: NWEndpoint.Host?
    private let listenPort: NWEndpoint.Port
    private let carHost: NWEndpoint.Host
    private let carPort: NWEndpoint.Port
    private let label: String
    private let queue: DispatchQueue
    private let stats: Stats?
    private var listener: NWListener?

    init(bind: String, listenPort: UInt16, carHost: String, carPort: UInt16, label: String, stats: Stats? = nil) {
        self.bindHost = (bind == "0.0.0.0" || bind.isEmpty) ? nil : NWEndpoint.Host(bind)
        self.listenPort = NWEndpoint.Port(rawValue: listenPort)!
        self.carHost = NWEndpoint.Host(carHost)
        self.carPort = NWEndpoint.Port(rawValue: carPort)!
        self.label = label
        self.stats = stats
        self.queue = DispatchQueue(label: "tcp.\(listenPort)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let bindHost = bindHost {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: bindHost, port: listenPort)
        }

        let listener = try NWListener(using: params, on: listenPort)
        self.listener = listener

        listener.stateUpdateHandler = { [label, listenPort] state in
            switch state {
            case .ready:
                Log.info("TCP \(listenPort) (\(label)) listening -> car:\(listenPort)")
            case .failed(let error):
                Log.error("TCP \(listenPort) (\(label)) failed: \(error)")
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
        Log.info("[\(label)] client \(client.endpoint) connected")
        let upstream = NWConnection(host: carHost, port: carPort, using: .tcp)
        TCPSession(client: client, upstream: upstream, label: label, queue: queue, stats: stats).start()
    }
}

/// One paired client<->car connection. Pumps data in both directions until
/// either side closes or errors.
private final class TCPSession {
    private let client: NWConnection
    private let upstream: NWConnection
    private let label: String
    private let queue: DispatchQueue
    private let stats: Stats?
    private var isClosed = false

    init(client: NWConnection, upstream: NWConnection, label: String, queue: DispatchQueue, stats: Stats?) {
        self.client = client
        self.upstream = upstream
        self.label = label
        self.queue = queue
        self.stats = stats
    }

    func start() {
        stats?.connectionOpened()
        upstream.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Log.info("[\(self?.label ?? "")] upstream ready (car)")
            case .failed(let error):
                Log.error("[\(self?.label ?? "")] upstream failed: \(error)")
                self?.close()
            case .cancelled:
                self?.close()
            default:
                break
            }
        }
        client.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                Log.warn("[\(self?.label ?? "")] client failed: \(error)")
                self?.close()
            case .cancelled:
                self?.close()
            default:
                break
            }
        }

        client.start(queue: queue)
        upstream.start(queue: queue)

        pump(from: client, to: upstream, direction: "esys->car")
        pump(from: upstream, to: client, direction: "car->esys")
    }

    private func pump(from source: NWConnection, to destination: NWConnection, direction: String) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, !self.isClosed else { return }

            if let data = data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { sendError in
                    if let sendError = sendError {
                        Log.warn("[\(self.label)] send \(direction) failed: \(sendError)")
                        self.close()
                    }
                })
            }

            if isComplete || error != nil {
                self.close()
                return
            }
            self.pump(from: source, to: destination, direction: direction)
        }
    }

    private func close() {
        queue.async { [weak self] in
            guard let self = self, !self.isClosed else { return }
            self.isClosed = true
            self.client.cancel()
            self.upstream.cancel()
            self.stats?.connectionClosed()
            Log.info("[\(self.label)] session closed")
        }
    }
}
