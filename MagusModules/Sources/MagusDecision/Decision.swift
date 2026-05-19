import Foundation
import MagusCore

/// Décision sortie du Decision Engine. Toujours accompagnée d'une explication
/// lisible (`explanation`) pour la confiance utilisateur.
public enum Decision: Sendable, Hashable {
    case applyRune(Rune, on: StatKind, explanation: String)
    case applyExo(slot: Pute.Slot, explanation: String)
    case applyAntiRune(Rune, on: StatKind, explanation: String)
    case finished(explanation: String)
    case waitingForUser(reason: String)
    case blocked(reason: BlockReason)

    public var explanation: String {
        switch self {
        case .applyRune(_, _, let e): return e
        case .applyExo(_, let e): return e
        case .applyAntiRune(_, _, let e): return e
        case .finished(let e): return e
        case .waitingForUser(let r): return r
        case .blocked(let r): return r.description
        }
    }
}

public enum BlockReason: Sendable, Hashable {
    case noItem
    case noPresetSelected
    case noItemSpec
    case ocrInsufficient(missing: [String])
    case runeOutOfStock(Rune)
    case noActionPossible(String)

    public var description: String {
        switch self {
        case .noItem: return "Aucun item détecté sur l'établi"
        case .noPresetSelected: return "Aucun preset sélectionné"
        case .noItemSpec: return "Item non sélectionné — choisis-le dans la carte « Item à mager »"
        case .ocrInsufficient(let missing): return "OCR insuffisant : \(missing.joined(separator: ", "))"
        case .runeOutOfStock(let r): return "Rune \(r.power.rawValue) manquante"
        case .noActionPossible(let m): return "Aucune action possible : \(m)"
        }
    }
}
