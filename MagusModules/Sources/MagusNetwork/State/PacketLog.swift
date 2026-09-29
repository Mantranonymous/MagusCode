import Foundation

/// Ring-buffer thread-safe pour la fenêtre Diagnostics : garde les N derniers
/// `DecodedMessage` observés.
///
/// Utilisé en lecture seule par l'UI ("dernier paquet décodé : X il y a Y ms").
public final class PacketLog: @unchecked Sendable {

    public struct Entry: Sendable {
        public let timestamp: Date
        public let message: DecodedMessage

        public init(timestamp: Date = Date(), message: DecodedMessage) {
            self.timestamp = timestamp
            self.message = message
        }
    }

    public let capacity: Int
    private var entries: [Entry] = []
    private let lock = NSLock()

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
        self.entries.reserveCapacity(capacity)
    }

    public func append(_ message: DecodedMessage) {
        lock.lock()
        entries.append(Entry(message: message))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        lock.unlock()
    }

    public func snapshot() -> [Entry] {
        lock.lock()
        let copy = entries
        lock.unlock()
        return copy
    }

    public func clear() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        let n = entries.count
        lock.unlock()
        return n
    }
}
