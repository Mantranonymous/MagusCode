import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.magus.network", category: "proxy")

/// Erreurs spécifiques au proxy local.
public enum DofusProxyError: Error, Sendable {
    case alreadyRunning
    case listenerFailed(reason: String)
    case invalidPreamble(received: String)
}

/// Listener TCP local **forward-only** : accepte les connexions du process
/// Dofus (qui ont été redirigées vers ce port par le hook Frida `connect()`),
/// extrait l'hôte distant du préambule, ouvre une connexion vers le vrai
/// serveur Ankama, et relaie les bytes dans les deux sens.
///
/// L'observation des messages se fait en side-channel : un `MessageStreamHub`
/// diffuse chaque `DecodedMessage` aux consumers (typiquement
/// `NetworkStateBuilder`).
public final class DofusProxy: @unchecked Sendable {

    /// Port d'écoute local.
    public let port: UInt16

    private let queue = DispatchQueue(label: "com.magus.network.proxy", qos: .userInitiated)
    private let hub = MessageStreamHub()
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [UUID: ProxyConnection] = [:]
    private var isRunning: Bool = false

    public init(port: UInt16 = 7975) {
        self.port = port
    }

    /// Démarre le listener. À appeler après que `FridaHelper` ait été lancé
    /// (ordre important : si Dofus tente de se connecter avant que le listener
    /// soit prêt, la connexion échoue).
    public func start() async throws {
        // On bascule l'initialisation sur la queue dédiée pour éviter de
        // toucher NSLock depuis un contexte async (warning Swift 6).
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                self.lock.lock()
                defer { self.lock.unlock() }
                guard !self.isRunning else {
                    cont.resume(throwing: DofusProxyError.alreadyRunning)
                    return
                }
                do {
                    let parameters = NWParameters.tcp
                    let nwPort = NWEndpoint.Port(rawValue: self.port) ?? .any
                    let listener = try NWListener(using: parameters, on: nwPort)
                    self.listener = listener
                    self.isRunning = true
                    cont.resume()
                } catch {
                    cont.resume(throwing: DofusProxyError.listenerFailed(reason: String(describing: error)))
                }
            }
        }

        guard let listener = self.listener else {
            throw DofusProxyError.listenerFailed(reason: "listener nil after init")
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("Proxy listening on 127.0.0.1:\(self.port, privacy: .public)")
            case .failed(let error):
                logger.error("Listener failed: \(String(describing: error), privacy: .public)")
            case .cancelled:
                logger.info("Listener cancelled")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleNewConnection(conn)
        }
        listener.start(queue: queue)
    }

    /// Arrête le listener et coupe toutes les connexions actives.
    public func stop() {
        lock.withLock {
            isRunning = false
            listener?.cancel()
            listener = nil
            for conn in connections.values {
                conn.stop()
            }
            connections.removeAll()
        }
        hub.finish()
    }

    /// Stream consommable des messages décodés.
    public func makeMessageStream() -> AsyncStream<DecodedMessage> {
        hub.makeStream()
    }

    /// Nb de connexions actives, pour debug UI.
    public var activeConnectionCount: Int {
        lock.withLock { connections.count }
    }

    /// Bytes cumulés observés (deux sens, toutes connexions confondues).
    public var totalBytesObserved: Int {
        lock.withLock { connections.values.reduce(0) { $0 + $1.bytesCount } }
    }

    // MARK: - Private

    private func handleNewConnection(_ conn: NWConnection) {
        logger.debug("New incoming connection")
        conn.start(queue: queue)
        // Lit le préambule `CONNECT host:port HTTP/1.0\r\n\r\n`.
        readPreamble(conn: conn)
    }

    private func readPreamble(conn: NWConnection, accumulated: Data = Data()) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                logger.warning("Preamble recv error: \(String(describing: error), privacy: .public)")
                conn.cancel()
                return
            }
            var acc = accumulated
            if let data { acc.append(data) }

            // Cherche la séquence "\r\n\r\n"
            let terminator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
            if let headerEnd = acc.range(of: Data(terminator)) {
                let header = acc.subdata(in: acc.startIndex..<headerEnd.lowerBound)
                let extra = acc.subdata(in: headerEnd.upperBound..<acc.endIndex)
                self.processPreamble(header: header, extraBytes: extra, conn: conn)
                return
            }

            if isComplete {
                logger.warning("Connection closed before preamble complete")
                conn.cancel()
                return
            }
            if acc.count > 4096 {
                logger.warning("Preamble too long, dropping connection")
                conn.cancel()
                return
            }
            // Pas encore complet → continue à lire
            self.readPreamble(conn: conn, accumulated: acc)
        }
    }

    private func processPreamble(header: Data, extraBytes: Data, conn: NWConnection) {
        guard let str = String(data: header, encoding: .ascii) else {
            logger.warning("Preamble not ASCII")
            conn.cancel()
            return
        }
        // Format attendu : "CONNECT <host>:<port> HTTP/1.0"
        let firstLine = str.split(separator: "\r\n", omittingEmptySubsequences: true).first.map(String.init) ?? str
        let tokens = firstLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2, tokens[0].uppercased() == "CONNECT" else {
            logger.warning("Invalid preamble: \(firstLine, privacy: .public)")
            conn.cancel()
            return
        }
        let hostPort = tokens[1]
        let parts = hostPort.split(separator: ":")
        guard parts.count == 2,
              let port = UInt16(parts[1])
        else {
            logger.warning("Invalid host:port in preamble: \(hostPort, privacy: .public)")
            conn.cancel()
            return
        }
        let host = String(parts[0])
        logger.info("Preamble OK: CONNECT \(host, privacy: .public):\(port, privacy: .public)")

        let proxyConn = ProxyConnection(
            clientConnection: conn,
            originHost: host,
            originPort: port,
            hub: hub,
            queue: queue
        )
        lock.withLock {
            connections[proxyConn.id] = proxyConn
        }
        proxyConn.start()

        // Si des bytes ont été lus après le terminator, on les pousse au framer
        // côté client→serveur en les forwardant manuellement via une 1ère send.
        // En pratique on délègue ça à `ProxyConnection.startRelay()` qui lira
        // les prochains bytes — les `extraBytes` sont les premiers vrais bytes
        // applicatifs : on doit les injecter.
        if !extraBytes.isEmpty {
            // Les `extraBytes` sont les premiers vrais bytes applicatifs
            // arrivés dans le même paquet TCP que le préambule. On les pousse
            // immédiatement au serveur upstream + au framer d'observation.
            proxyConn.injectInitialClientBytes(extraBytes)
        }
    }
}
