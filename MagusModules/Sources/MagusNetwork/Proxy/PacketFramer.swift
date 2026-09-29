import Foundation
import os

private let logger = Logger(subsystem: "com.magus.network", category: "framer")

/// Stratégie de framing à utiliser pour scinder un flux TCP en messages
/// Protobuf individuels.
///
/// Le framing exact utilisé par Dofus 3 n'est pas confirmé à 100 %, donc
/// `PacketFramer` supporte les deux variantes connues du protocole binaire
/// Ankama et peut bascule automatiquement de `varint` → `uint32BE` si la
/// première strategy échoue à plusieurs reprises.
public enum FramingStrategy: String, Sendable, CaseIterable {
    /// Length-prefix varint (style Protobuf delimited).
    case varint
    /// Length-prefix uint32 big-endian (style Ankama legacy / Hyperion).
    case uint32BE

    public var displayName: String {
        switch self {
        case .varint: return "Varint length-prefix"
        case .uint32BE: return "UInt32-BE length-prefix"
        }
    }
}

/// Erreur de framing : le framer ne sait pas où couper le prochain message.
public enum FramerError: Error, Sendable {
    case lengthTooLarge(reportedLength: Int, max: Int)
    case invalidVarint
}

/// Accumule des bytes provenant d'un flux TCP et produit des frames Protobuf
/// complètes au fur et à mesure qu'elles arrivent.
///
/// Thread-safety : un `PacketFramer` doit être utilisé depuis un seul contexte
/// (par exemple dans une `Task` dédiée à une `ProxyConnection`). Il n'est pas
/// `Sendable` car il maintient un buffer mutable.
public final class PacketFramer {

    /// Limite haute sur la taille d'un message protobuf annoncé par le
    /// length-prefix. Si on lit une longueur supérieure, on considère que le
    /// framing est mal aligné et on rapporte une erreur pour permettre un
    /// éventuel switch de strategy.
    public static let maxFrameSize = 16 * 1024 * 1024 // 16 MB

    public private(set) var strategy: FramingStrategy
    private var buffer = Data()
    private var consecutiveFailures: Int = 0
    private let autoSwitchThreshold: Int

    /// - Parameters:
    ///   - strategy: framing initial à essayer.
    ///   - autoSwitchThreshold: nombre d'échecs consécutifs avant de basculer
    ///     automatiquement vers l'autre stratégie. `0` = jamais basculer.
    public init(strategy: FramingStrategy = .varint, autoSwitchThreshold: Int = 3) {
        self.strategy = strategy
        self.autoSwitchThreshold = max(0, autoSwitchThreshold)
    }

    /// Reset complet : flush le buffer et remet les compteurs à zéro. À appeler
    /// quand on est sûr que le côté distant a fermé.
    public func reset() {
        buffer.removeAll(keepingCapacity: true)
        consecutiveFailures = 0
    }

    /// Force manuellement une strategy (et flush le buffer accumulé).
    public func setStrategy(_ strategy: FramingStrategy) {
        self.strategy = strategy
        buffer.removeAll(keepingCapacity: true)
        consecutiveFailures = 0
    }

    /// Pousse de nouveaux bytes dans le buffer. À appeler à chaque chunk TCP
    /// reçu côté observation.
    public func push(_ chunk: Data) {
        buffer.append(chunk)
    }

    /// Tente d'extraire la prochaine frame complète. Retourne `nil` s'il n'y a
    /// pas encore assez de bytes pour une frame entière, ou si le framing est
    /// mal aligné (auquel cas un éventuel switch automatique a déjà eu lieu).
    ///
    /// Le caller peut appeler `nextFrame()` en boucle jusqu'à `nil` pour
    /// drainer toutes les frames disponibles dans le buffer.
    public func nextFrame() -> Data? {
        do {
            guard let frame = try tryExtract() else { return nil }
            consecutiveFailures = 0
            return frame
        } catch {
            consecutiveFailures += 1
            logger.warning("Framing failure (\(self.consecutiveFailures)) on strategy=\(self.strategy.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            // Si on dépasse le seuil, on tente l'autre strategy. C'est un peu
            // brutal — on perd les bytes déjà accumulés — mais c'est la seule
            // façon de récupérer sans connaître à l'avance le bon framing.
            if autoSwitchThreshold > 0 && consecutiveFailures >= autoSwitchThreshold {
                let other: FramingStrategy = (strategy == .varint) ? .uint32BE : .varint
                logger.warning("Auto-switch framing strategy: \(self.strategy.rawValue, privacy: .public) → \(other.rawValue, privacy: .public)")
                setStrategy(other)
            }
            return nil
        }
    }

    // MARK: - Private

    private func tryExtract() throws -> Data? {
        switch strategy {
        case .varint:
            return try tryExtractVarint()
        case .uint32BE:
            return try tryExtractUInt32BE()
        }
    }

    private func tryExtractVarint() throws -> Data? {
        guard !buffer.isEmpty else { return nil }
        var lengthValue: UInt64 = 0
        var shift: UInt64 = 0
        var lengthBytes = 0
        for byte in buffer {
            lengthBytes += 1
            lengthValue |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                break
            }
            shift += 7
            if shift >= 64 || lengthBytes > 10 {
                throw FramerError.invalidVarint
            }
        }
        // Varint pas terminé encore → attendre plus de bytes
        if lengthBytes > 0 && (buffer[buffer.startIndex + lengthBytes - 1] & 0x80) != 0 {
            return nil
        }
        let length = Int(lengthValue)
        if length < 0 || length > Self.maxFrameSize {
            throw FramerError.lengthTooLarge(reportedLength: length, max: Self.maxFrameSize)
        }
        let totalNeeded = lengthBytes + length
        if buffer.count < totalNeeded { return nil }
        let frame = buffer.subdata(in: buffer.index(buffer.startIndex, offsetBy: lengthBytes)..<buffer.index(buffer.startIndex, offsetBy: totalNeeded))
        buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: totalNeeded))
        return frame
    }

    private func tryExtractUInt32BE() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let lengthBytes = buffer.prefix(4)
        var length: UInt32 = 0
        for byte in lengthBytes {
            length = (length << 8) | UInt32(byte)
        }
        let lengthInt = Int(length)
        if lengthInt > Self.maxFrameSize {
            throw FramerError.lengthTooLarge(reportedLength: lengthInt, max: Self.maxFrameSize)
        }
        let totalNeeded = 4 + lengthInt
        if buffer.count < totalNeeded { return nil }
        let frame = buffer.subdata(in: buffer.index(buffer.startIndex, offsetBy: 4)..<buffer.index(buffer.startIndex, offsetBy: totalNeeded))
        buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: totalNeeded))
        return frame
    }
}
