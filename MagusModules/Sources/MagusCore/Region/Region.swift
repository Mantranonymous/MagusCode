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
    /// Cellule de la rune Ga Pa dans l'inventaire (pour poser un exo PA).
    /// La stat PA n'apparaît pas dans la table FM si l'item n'a pas de PA natif,
    /// donc on doit cliquer la rune directement depuis l'inventaire.
    case runeSlotGaPa
    /// Cellule de la rune Ga Pme dans l'inventaire (pour poser un exo PM).
    case runeSlotGaPme
    /// Cellule de la rune Po dans l'inventaire (pour poser un exo Portée).
    case runeSlotPo
    /// Cellule de la rune Pa Do Sort en inventaire (exo % Do Sort).
    case runeSlotPaDoSort
    /// Cellule de la rune Pa Do Distance en inventaire (exo % Do Distance).
    case runeSlotPaDoDistance
    /// Bouton "Fusionner" du panneau Joaillomager. Après avoir sélectionné une
    /// rune en inventaire pour un exo, il faut cliquer ce bouton pour valider
    /// la fusion — Dofus 3 ne pose pas la rune sur double-clic depuis l'inventaire.
    case fuserButton

    public var dataType: RegionDataType {
        switch self {
        case .stats, .history, .reliquat, .jobLevel:
            return .text
        case .runeInventory, .xpBar, .statsPaColumn, .statsRaColumn, .statsBaseColumn,
             .runeSlotGaPa, .runeSlotGaPme, .runeSlotPo,
             .runeSlotPaDoSort, .runeSlotPaDoDistance, .fuserButton:
            return .visual
        }
    }

    /// Vrai si cette région est strictement nécessaire pour le pipeline OCR.
    /// Les régions optionnelles (colonnes click, slots inventaire) ne bloquent pas isComplete.
    public var isRequired: Bool {
        switch self {
        case .stats, .history, .reliquat, .jobLevel: return true
        case .runeInventory, .xpBar: return false
        case .statsPaColumn, .statsRaColumn, .statsBaseColumn: return false
        case .runeSlotGaPa, .runeSlotGaPme, .runeSlotPo: return false
        case .runeSlotPaDoSort, .runeSlotPaDoDistance: return false
        case .fuserButton: return false
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
        case .runeSlotGaPa: return "Rune Ga PA en inventaire (exo PA)"
        case .runeSlotGaPme: return "Rune Ga PME en inventaire (exo PM)"
        case .runeSlotPo: return "Rune Po en inventaire (exo Portée)"
        case .runeSlotPaDoSort: return "Rune Pa Do Sort en inventaire (exo % Sort)"
        case .runeSlotPaDoDistance: return "Rune Pa Do Distance en inventaire (exo % Distance)"
        case .fuserButton: return "Bouton Fusionner (valide la rune exo sélectionnée)"
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
        case .runeSlotGaPa: return "Slot Ga PA"
        case .runeSlotGaPme: return "Slot Ga PME"
        case .runeSlotPo: return "Slot Po"
        case .runeSlotPaDoSort: return "Slot Pa Do Sort"
        case .runeSlotPaDoDistance: return "Slot Pa Do Dist"
        case .fuserButton: return "Fusionner"
        }
    }
}

/// Nature des données à extraire d'une région.
public enum RegionDataType: String, Sendable {
    case text    // OCR via Vision/VLM
    case visual  // analyse pixel (barre de progression, couleur, etc.)
}
