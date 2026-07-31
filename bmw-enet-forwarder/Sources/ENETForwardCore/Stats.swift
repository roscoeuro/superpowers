import Foundation

/// Thread-safe live counters shared by the relays and surfaced to the UI.
public final class Stats {
    private let lock = NSLock()
    private var _activeConnections = 0
    private var _totalConnections = 0

    public init() {}

    public func connectionOpened() {
        lock.lock(); _activeConnections += 1; _totalConnections += 1; lock.unlock()
    }

    public func connectionClosed() {
        lock.lock(); if _activeConnections > 0 { _activeConnections -= 1 }; lock.unlock()
    }

    public var activeConnections: Int {
        lock.lock(); defer { lock.unlock() }; return _activeConnections
    }

    public var totalConnections: Int {
        lock.lock(); defer { lock.unlock() }; return _totalConnections
    }
}
