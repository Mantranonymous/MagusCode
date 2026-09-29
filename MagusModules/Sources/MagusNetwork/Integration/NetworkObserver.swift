import Foundation
import MagusCore
import os
import SwiftUI

private let logger = Logger(subsystem: "com.magus.network", category: "observer")

/// Facade publique du module MagusNetwork.
///
/// Orchestre les trois acteurs :
/// 1. `FridaHelper` — spawn Dofus + hook libc connect()
/// 2. `DofusProxy` — listener TCP local forward-only
/// 3. `NetworkStateBuilder` — convertit les events en `GameStateSnapshot`
///
/// Le consumer typique (`AppState`) :
/// - toggle `start(port:dofusPath:)` quand l'utilisateur active l'option
/// - consomme `snapshotStream` pour rafraîchir `lastParsedSnapshot`
/// - observe `isObserving` / `packetCount` / `lastError` pour l'UI
@MainActor
public final class NetworkObserver: ObservableObject {

    @Published public private(set) var isObserving: Bool = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var packetCount: Int = 0
    @Published public private(set) var lastEvent: String?
    @Published public private(set) var dofusPid: Int32?
    @Published public private(set) var redirectedConnectionCount: Int = 0

    public let packetLog: PacketLog
    private let fridaScriptDirectory: URL

    private var fridaHelper: FridaHelper?
    private var proxy: DofusProxy?
    private var stateBuilder: NetworkStateBuilder?
    private var consumerTask: Task<Void, Never>?
    private var pollerTask: Task<Void, Never>?

    /// - Parameter fridaScriptDirectory: dossier qui contient
    ///   `frida-spawn-dofus.js` + `package.json`. Par défaut, on cherche dans
    ///   le bundle de l'app (`Bundle.main.resourceURL/MagusNetwork/Frida`).
    public init(fridaScriptDirectory: URL? = nil) {
        self.packetLog = PacketLog(capacity: 500)
        if let dir = fridaScriptDirectory {
            self.fridaScriptDirectory = dir
        } else if let bundleScripts = Bundle.main.resourceURL?.appendingPathComponent("MagusNetwork/Frida"),
                  FileManager.default.fileExists(atPath: bundleScripts.path) {
            self.fridaScriptDirectory = bundleScripts
        } else {
            // Fallback : utilise le dossier source dans le repo (dev only).
            let fallback = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Desktop/perso/MagusCode/MagusModules/Sources/MagusNetwork/Frida")
            self.fridaScriptDirectory = fallback
        }
    }

    /// Démarre observation : proxy d'abord, puis helper Frida.
    public func start(port: UInt16, dofusPath: URL?) async throws {
        if isObserving { return }
        lastError = nil
        packetCount = 0
        redirectedConnectionCount = 0

        let proxy = DofusProxy(port: port)
        try await proxy.start()
        let stateBuilder = NetworkStateBuilder(packetLog: packetLog)
        let messageStream = proxy.makeMessageStream()
        let consumeTask = Task {
            await stateBuilder.consume(stream: messageStream)
        }

        let helper = FridaHelper(scriptDirectory: fridaScriptDirectory)
        helper.onEvent = { [weak self] event in
            self?.handleFridaEvent(event)
        }
        do {
            try await helper.start(proxyPort: port, dofusPath: dofusPath)
        } catch {
            proxy.stop()
            consumeTask.cancel()
            throw error
        }

        self.proxy = proxy
        self.stateBuilder = stateBuilder
        self.fridaHelper = helper
        self.consumerTask = consumeTask
        self.isObserving = true

        // Poller léger pour rafraîchir packetCount dans l'UI.
        pollerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.refreshCounters()
                }
                let still = await MainActor.run { self?.isObserving ?? false }
                if !still { break }
            }
        }
        logger.info("NetworkObserver started")
    }

    /// Test rapide sans démarrer une vraie session FM : lance juste Frida
    /// pour vérifier que Dofus se spawn et que le hook s'installe. Coupe
    /// tout après la confirmation (ou timeout).
    public func runDiagnostic(port: UInt16, dofusPath: URL?) async throws -> String {
        if isObserving {
            stop()
        }
        var lines: [String] = []
        let helper = FridaHelper(scriptDirectory: fridaScriptDirectory)
        var receivedReady = false
        var receivedPid: Int32?
        let lock = NSLock()
        helper.onEvent = { event in
            lock.lock(); defer { lock.unlock() }
            switch event {
            case .pid(let p):
                receivedPid = p
                lines.append("PID Dofus : \(p)")
            case .hookInstalled:
                lines.append("Hook libc connect() installé")
            case .ready:
                receivedReady = true
                lines.append("READY")
            case .error(let msg):
                lines.append("ERROR: \(msg)")
            case .connectRedirected(let host, let port):
                lines.append("Connexion observée → \(host):\(port)")
            case .stopping(let s):
                lines.append("Stopping (\(s))")
            case .rawLine(let l):
                lines.append(l)
            }
        }
        try await helper.start(proxyPort: port, dofusPath: dofusPath)
        // Attente max 8s pour READY
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && !receivedReady {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        helper.stop()
        if !receivedReady {
            throw FridaError.attachRefused(detail: lines.joined(separator: " | "))
        }
        let pidStr = receivedPid.map { "PID=\($0)" } ?? "?"
        return "Diagnostic OK (\(pidStr))\n" + lines.joined(separator: "\n")
    }

    public func stop() {
        consumerTask?.cancel()
        pollerTask?.cancel()
        fridaHelper?.stop()
        proxy?.stop()
        consumerTask = nil
        pollerTask = nil
        fridaHelper = nil
        proxy = nil
        stateBuilder = nil
        isObserving = false
        logger.info("NetworkObserver stopped")
    }

    /// Stream des snapshots reconstruits depuis le réseau. Le consumer doit
    /// fusionner ça avec les snapshots OCR (le réseau est prioritaire sur les
    /// champs qu'il fournit ; l'OCR reste source unique pour le reste).
    ///
    /// **Important** : à appeler APRÈS `start(port:dofusPath:)`, sinon retourne
    /// un stream qui se termine immédiatement.
    public func snapshotStream() async -> AsyncStream<GameStateSnapshot> {
        guard let builder = stateBuilder else {
            return AsyncStream { $0.finish() }
        }
        return await builder.snapshotStream()
    }

    // MARK: - Private

    private func handleFridaEvent(_ event: FridaHelper.Event) {
        switch event {
        case .pid(let p):
            self.dofusPid = p
            self.lastEvent = "PID Dofus : \(p)"
        case .hookInstalled:
            self.lastEvent = "Hook libc connect() installé"
        case .ready:
            self.lastEvent = "Frida prêt"
        case .connectRedirected(let host, let port):
            self.redirectedConnectionCount += 1
            self.lastEvent = "Redirigé \(host):\(port) → 127.0.0.1"
        case .stopping(let s):
            self.lastEvent = "Frida stopping (\(s))"
        case .error(let msg):
            self.lastError = msg
            self.lastEvent = "ERROR: \(msg)"
            logger.warning("Frida error: \(msg, privacy: .public)")
        case .rawLine(let l):
            // Pas spammer les logs sur les lignes hors protocole
            if !l.isEmpty {
                logger.debug("frida raw: \(l, privacy: .public)")
            }
        }
    }

    private func refreshCounters() {
        self.packetCount = packetLog.count
    }
}
