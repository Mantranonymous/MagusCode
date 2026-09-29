import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.magus.network", category: "proxy-conn")

/// Une connexion proxifiée : un client (Dofus) se connecte au listener local,
/// et `ProxyConnection` ouvre une seconde connexion vers le vrai serveur Ankama
/// puis relaie les bytes dans les deux sens **sans aucune modification**.
///
/// L'observation des bytes en transit se fait via deux `PacketFramer` (un par
/// sens). Chaque frame complète obtenue est passée au `PacketDecoder` et le
/// résultat est diffusé sur le hub commun.
///
/// **Garantie de transparence** : si le framer ou le decoder throw / crash,
/// le forward continue. Le pire qui puisse arriver est de perdre la décodage
/// d'un message, jamais d'interrompre la session de jeu.
public final class ProxyConnection: @unchecked Sendable {

    /// Identifiant unique pour debug / logs.
    public let id: UUID = UUID()

    /// L'hôte distant tel qu'extrait du préambule `CONNECT host:port`.
    public let originHost: String
    public let originPort: UInt16

    private let clientConnection: NWConnection
    private let serverConnection: NWConnection
    private let queue: DispatchQueue

    private let decoder = PacketDecoder()
    private let framerClientToServer = PacketFramer(strategy: .varint)
    private let framerServerToClient = PacketFramer(strategy: .varint)
    private let hub: MessageStreamHub

    private let bytesObserved = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Initialiseur appelé par `DofusProxy` après avoir reçu le préambule
    /// `CONNECT host:port`.
    public init(
        clientConnection: NWConnection,
        originHost: String,
        originPort: UInt16,
        hub: MessageStreamHub,
        queue: DispatchQueue
    ) {
        self.clientConnection = clientConnection
        self.originHost = originHost
        self.originPort = originPort
        self.hub = hub
        self.queue = queue
        let host = NWEndpoint.Host(originHost)
        let port = NWEndpoint.Port(rawValue: originPort) ?? .any
        self.serverConnection = NWConnection(host: host, port: port, using: .tcp)
    }

    /// Démarre le forward bidirectionnel.
    public func start() {
        serverConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                logger.debug("Connected upstream to \(self.originHost, privacy: .public):\(self.originPort, privacy: .public) [id=\(self.id, privacy: .public)]")
                self.startRelay()
            case .failed(let error):
                logger.error("Upstream connection failed: \(String(describing: error), privacy: .public)")
                self.stop()
            case .cancelled:
                logger.debug("Upstream cancelled [id=\(self.id, privacy: .public)]")
            default:
                break
            }
        }
        serverConnection.start(queue: queue)
    }

    /// Coupe les deux côtés.
    public func stop() {
        clientConnection.cancel()
        serverConnection.cancel()
    }

    /// Total cumulé d'octets observés sur cette connexion (deux sens
    /// confondus). Utile pour la barre d'état UI.
    public var bytesCount: Int {
        bytesObserved.withLock { $0 }
    }

    /// Forward immédiat des bytes vers le serveur upstream + observation.
    /// Utilisé par `DofusProxy` pour traiter les bytes qui suivaient
    /// directement le préambule `CONNECT …\r\n\r\n` dans le même paquet TCP.
    public func injectInitialClientBytes(_ data: Data) {
        guard !data.isEmpty else { return }
        serverConnection.send(content: data, completion: .contentProcessed { sendError in
            if let sendError {
                logger.warning("Initial inject send error: \(String(describing: sendError), privacy: .public)")
            }
        })
        bytesObserved.withLock { $0 += data.count }
        framerClientToServer.push(data)
        while let frame = framerClientToServer.nextFrame() {
            let msg = decoder.decode(frame, direction: .clientToServer)
            hub.broadcast(msg)
        }
    }

    // MARK: - Private

    private func startRelay() {
        // Client → Server
        receiveLoop(
            from: clientConnection,
            to: serverConnection,
            framer: framerClientToServer,
            direction: .clientToServer
        )
        // Server → Client
        receiveLoop(
            from: serverConnection,
            to: clientConnection,
            framer: framerServerToClient,
            direction: .serverToClient
        )
    }

    private func receiveLoop(
        from source: NWConnection,
        to destination: NWConnection,
        framer: PacketFramer,
        direction: DecodedMessage.Direction
    ) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                logger.warning("Recv error (\(String(describing: direction), privacy: .public)): \(String(describing: error), privacy: .public)")
                self.stop()
                return
            }
            if let data, !data.isEmpty {
                // 1. Forward IMMÉDIAT, intact.
                destination.send(content: data, completion: .contentProcessed { sendError in
                    if let sendError {
                        logger.warning("Send error: \(String(describing: sendError), privacy: .public)")
                    }
                })

                // 2. Side-channel : push dans le framer et drain.
                self.bytesObserved.withLock { $0 += data.count }
                framer.push(data)
                while let frame = framer.nextFrame() {
                    let msg = self.decoder.decode(frame, direction: direction)
                    self.hub.broadcast(msg)
                }
            }
            if isComplete {
                logger.debug("Half-close (\(String(describing: direction), privacy: .public)) [id=\(self.id, privacy: .public)]")
                destination.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                return
            }
            // Continue le loop
            self.receiveLoop(from: source, to: destination, framer: framer, direction: direction)
        }
    }
}
