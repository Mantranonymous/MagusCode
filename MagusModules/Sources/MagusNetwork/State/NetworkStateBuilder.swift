import Foundation
import MagusCore
import os

private let logger = Logger(subsystem: "com.magus.network", category: "state-builder")

/// Convertit le flux d'événements réseau (`DecodedMessage`) en une suite de
/// `GameStateSnapshot` reflétant l'état actuel de la session de forgemagie.
///
/// Statut : **scaffolding**. Tant que les `.pb.swift` ne sont pas générés, ce
/// builder ne peut pas extraire les valeurs réelles (item, runes, résultat
/// SC/SN/EC, etc.) — il maintient un état squelettique qu'il met à jour avec
/// les seuls signaux dont il peut être sûr (réception d'un événement reconnu).
///
/// Une fois les types Swift générés, remplacer chaque section `// TODO: extract
/// value from protobuf XYZ` par un vrai parsing des champs.
public actor NetworkStateBuilder {

    private var currentSnapshot: GameStateSnapshot
    private var continuation: AsyncStream<GameStateSnapshot>.Continuation?
    private let packetLog: PacketLog
    private var lastEmitTask: Task<Void, Never>?

    /// Délai de debounce avant d'émettre un nouveau snapshot, pour éviter de
    /// spammer les consumers quand plusieurs events arrivent dans la même ms.
    private let debounceInterval: TimeInterval = 0.1

    public init(packetLog: PacketLog) {
        self.packetLog = packetLog
        self.currentSnapshot = GameStateSnapshot()
    }

    /// Stream consommable des snapshots reconstruits.
    public func snapshotStream() -> AsyncStream<GameStateSnapshot> {
        let snapshotNow = currentSnapshot
        return AsyncStream { continuation in
            // L'actor isolation est respectée parce que `continuation` est
            // une référence Sendable et qu'on l'assigne via une Task isolée.
            Task { [weak self] in
                await self?.setContinuation(continuation)
            }
            continuation.yield(snapshotNow)
        }
    }

    private func setContinuation(_ continuation: AsyncStream<GameStateSnapshot>.Continuation) {
        self.continuation = continuation
    }

    /// Branche le builder sur un stream de messages décodés (typiquement
    /// fourni par `DofusProxy.makeMessageStream()`).
    public func consume(stream: AsyncStream<DecodedMessage>) async {
        for await message in stream {
            await ingest(message)
        }
    }

    /// Reset complet (à appeler entre deux sessions).
    public func reset() {
        currentSnapshot = GameStateSnapshot()
        scheduleEmit()
    }

    /// Snapshot le plus récent (lecture seule).
    public func current() -> GameStateSnapshot {
        currentSnapshot
    }

    // MARK: - Private

    private func ingest(_ message: DecodedMessage) async {
        packetLog.append(message)

        switch message {
        case .exchangeStarted, .exchangeRunesTradeStarted:
            // Nouvelle session FM démarrée → on reset l'item + l'historique.
            // TODO: extract initial item from `ExchangeStartedEvent` payload.
            logger.debug("FM session started (\(message.shortLabel, privacy: .public))")
            currentSnapshot = GameStateSnapshot(timestamp: Date())

        case .exchangeObjectsAdded:
            // Le serveur a posé un nouvel item sur l'établi.
            // TODO: extract item from `ExchangeObjectsAddedEvent.objects[0]`
            //       puis mapper `ObjectItem.effects[]` vers `[Stat]` via la
            //       table caractéristiques (id_action → StatKind).
            logger.debug("ExchangeObjectsAdded — TODO extract item")

        case .exchangeObjectsModified:
            // L'item a changé (combine landed). On veut juste mettre à jour
            // les stats.
            // TODO: extract updated stats from `ExchangeObjectsModifiedEvent`.
            logger.debug("ExchangeObjectsModified — TODO update stats")

        case .exchangeCraftResult:
            // Une rune vient d'être combinée → on ajoute une entrée historique.
            // TODO: extract `CraftResult` (SUCCESS / NEUTRAL / FAILED), le
            //       `fm_power` (nouveau reliquat), et la stat ciblée.
            logger.debug("ExchangeCraftResult — TODO append history entry")

        case .exchangeLeave:
            logger.debug("ExchangeLeave — session closed")
            // On garde le snapshot courant, l'utilisateur peut vouloir le voir.

        case .unknown(let typeUrl, _, _):
            logger.debug("Unknown message: \(typeUrl, privacy: .public)")

        case .decodeError(let reason, _, _):
            logger.warning("Decode error: \(reason, privacy: .public)")
        }

        scheduleEmit()
    }

    /// Debounce : annule la précédente émission et planifie une nouvelle après
    /// `debounceInterval`. Évite de réveiller le consumer 50 fois par seconde
    /// si plusieurs events tombent en rafale.
    private func scheduleEmit() {
        lastEmitTask?.cancel()
        let snapshot = currentSnapshot
        let cont = continuation
        let interval = debounceInterval
        lastEmitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            cont?.yield(snapshot)
            _ = self
        }
    }
}
