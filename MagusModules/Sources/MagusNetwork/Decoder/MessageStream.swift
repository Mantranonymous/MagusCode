import Foundation

/// Petit helper d'agrégation : multiplexe les `DecodedMessage` produits par
/// plusieurs `ProxyConnection` en un unique `AsyncStream` consommable.
///
/// Pourquoi : `DofusProxy` peut accepter plusieurs connexions concurrentes
/// (login server + game server + auth, etc.), mais le consumer côté `AppState`
/// veut juste un seul flux ordonné de messages.
public final class MessageStreamHub: @unchecked Sendable {

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<DecodedMessage>.Continuation] = [:]

    public init() {}

    /// Crée un nouveau stream. Le consumer doit retenir le retour du closure
    /// `onTerminate` pour pouvoir se désabonner proprement.
    public func makeStream() -> AsyncStream<DecodedMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            self.lock.lock()
            self.continuations[id] = continuation
            self.lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    /// Diffuse un message à tous les streams actifs.
    public func broadcast(_ message: DecodedMessage) {
        lock.lock()
        let conts = Array(continuations.values)
        lock.unlock()
        for cont in conts {
            cont.yield(message)
        }
    }

    /// Termine tous les streams (à appeler à `stop()` du proxy).
    public func finish() {
        lock.lock()
        let conts = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for cont in conts {
            cont.finish()
        }
    }
}
