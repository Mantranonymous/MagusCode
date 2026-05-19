import Foundation

/// Une "pute" = une exo, modification rare obtenue via combine spécifique.
/// Les slots d'exo standards en Dofus.
public struct Pute: Hashable, Codable, Sendable {

    public enum Slot: String, Codable, CaseIterable, Sendable {
        case pa          // exo PA (Point d'Action)
        case pm          // exo PM (Point de Mouvement)
        case ra          // exo Portée
        case crit        // exo Critique
        case inv         // exo Invocation
        case dommages    // exo Dommages
        case portee      // exo Portée (alias de ra dans certains contextes)

        public var displayName: String {
            switch self {
            case .pa: return "PA"
            case .pm: return "PM"
            case .ra: return "RA"
            case .crit: return "Crit"
            case .inv: return "Invocation"
            case .dommages: return "Dommages"
            case .portee: return "Portée"
            }
        }
    }

    public let slot: Slot
    public let value: Int

    public init(slot: Slot, value: Int) {
        self.slot = slot
        self.value = value
    }
}
