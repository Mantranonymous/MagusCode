import Foundation

/// Profil de FM d'un item — détermine la stratégie à appliquer.
/// Voir mémoire `forgemagie-domain`.
public enum ItemProfile: String, Codable, CaseIterable, Sendable {
    /// Pas de grosse stat unique → jongler entre lignes, concessions sur secondaires.
    case concessions

    /// Possède une grosse stat (PA/PM/PO) → exploitable comme puits de reliquat.
    /// Recommandé pour débutants.
    case puits

    /// Pas de puits naturel → nécessite un exo PA/PM puis brisage pour créer reliquat.
    case brisages

    /// Inconnu / pas encore déterminé (premier OCR sans assez d'info).
    case unknown

    public var displayName: String {
        switch self {
        case .concessions: return "À concessions"
        case .puits: return "À puits"
        case .brisages: return "À brisages"
        case .unknown: return "Indéterminé"
        }
    }

    public var explanation: String {
        switch self {
        case .concessions:
            return "Pas de grosse stat unique. On jongle entre les lignes en faisant des concessions sur les stats secondaires."
        case .puits:
            return "Une grosse stat (PA/PM/PO) génère un fort reliquat quand elle tombe. Exploite ce puits pour monter le reste."
        case .brisages:
            return "Pas de puits naturel. Stratégie avancée : exo PA temporaire puis brisage pour créer du reliquat."
        case .unknown:
            return "Profil pas encore déterminé."
        }
    }
}
