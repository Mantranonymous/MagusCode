import Foundation

/// Une entrée dans l'historique des combines forgemagie.
public struct MageHistoryEntry: Hashable, Codable, Sendable, Identifiable {

    public enum Result: String, Codable, Sendable {
        /// SC — Succès Critique : la rune passe sans contrepartie.
        case criticalSuccess
        /// SN — Succès Neutre : la rune passe mais retire son poids ailleurs.
        case neutralSuccess
        /// EC — Échec Critique : la rune échoue ET retire son poids.
        case criticalFail
        case unknown

        public var shortLabel: String {
            switch self {
            case .criticalSuccess: return "SC"
            case .neutralSuccess: return "SN"
            case .criticalFail: return "EC"
            case .unknown: return "?"
            }
        }
    }

    public enum CombineKind: String, Codable, Sendable {
        case smRune
        case raRune
        case paRune
        case smInverse
        case raInverse
        case paInverse
        case puteExo
        case puteInverse
        case unknown
    }

    public let id: UUID
    public let result: Result
    public let kind: CombineKind
    public let targetStat: StatKind?
    public let delta: Int            // gain ou perte de stat
    public let raw: String           // ligne brute OCR, pour debug

    public init(
        id: UUID = UUID(),
        result: Result,
        kind: CombineKind,
        targetStat: StatKind? = nil,
        delta: Int = 0,
        raw: String = ""
    ) {
        self.id = id
        self.result = result
        self.kind = kind
        self.targetStat = targetStat
        self.delta = delta
        self.raw = raw
    }
}
