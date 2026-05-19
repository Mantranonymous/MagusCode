import Foundation

/// Région d'intérêt sur la fenêtre du jeu (Stats, Historique, etc.).
public struct Region: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let kind: RegionKind
    public var bounds: NormalizedRect

    public init(id: UUID = UUID(), kind: RegionKind, bounds: NormalizedRect) {
        self.id = id
        self.kind = kind
        self.bounds = bounds
    }
}

/// Types de régions calibrables sur l'interface de forgemagie.
public enum RegionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case stats
    case history
    case reliquat
    case runeInventory
    case jobLevel
    case xpBar

    public var dataType: RegionDataType {
        switch self {
        case .stats, .history, .reliquat, .jobLevel:
            return .text
        case .runeInventory, .xpBar:
            return .visual
        }
    }

    public var displayName: String {
        switch self {
        case .stats: return "Stats de l'item"
        case .history: return "Historique des combines"
        case .reliquat: return "Reliquat (puits)"
        case .runeInventory: return "Inventaire des runes"
        case .jobLevel: return "Niveau métier"
        case .xpBar: return "Barre d'expérience"
        }
    }

    public var shortName: String {
        switch self {
        case .stats: return "Stats"
        case .history: return "Historique"
        case .reliquat: return "Reliquat"
        case .runeInventory: return "Runes"
        case .jobLevel: return "Niveau"
        case .xpBar: return "XP"
        }
    }
}

/// Nature des données à extraire d'une région.
public enum RegionDataType: String, Sendable {
    case text    // OCR via Vision/VLM
    case visual  // analyse pixel (barre de progression, couleur, etc.)
}
