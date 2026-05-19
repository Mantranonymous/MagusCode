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
    /// Colonne Pa de la stats table (bande verticale fine) — utilisée pour
    /// calculer la position X précise du click auto.
    case statsPaColumn
    /// Colonne Ra de la stats table (bande verticale fine).
    case statsRaColumn
    /// Colonne Modif / runes base de la stats table (bande verticale fine).
    case statsBaseColumn

    public var dataType: RegionDataType {
        switch self {
        case .stats, .history, .reliquat, .jobLevel:
            return .text
        case .runeInventory, .xpBar, .statsPaColumn, .statsRaColumn, .statsBaseColumn:
            return .visual
        }
    }

    /// Vrai si cette région est strictement nécessaire pour le pipeline OCR.
    /// Les régions optionnelles (colonnes click) ne bloquent pas isComplete.
    public var isRequired: Bool {
        switch self {
        case .stats, .history, .reliquat, .jobLevel: return true
        case .runeInventory, .xpBar: return false
        case .statsPaColumn, .statsRaColumn, .statsBaseColumn: return false
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
        case .statsPaColumn: return "Colonne Pa (pour click auto)"
        case .statsRaColumn: return "Colonne Ra (pour click auto)"
        case .statsBaseColumn: return "Colonne Modif/base (pour click auto)"
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
        case .statsPaColumn: return "Col Pa"
        case .statsRaColumn: return "Col Ra"
        case .statsBaseColumn: return "Col Modif"
        }
    }
}

/// Nature des données à extraire d'une région.
public enum RegionDataType: String, Sendable {
    case text    // OCR via Vision/VLM
    case visual  // analyse pixel (barre de progression, couleur, etc.)
}
