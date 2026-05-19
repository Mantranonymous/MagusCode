import Foundation

/// Information d'over sur une stat : combien de densité a été placée au-delà du max.
/// Cap absolu : 101 densité d'over par stat.
public struct OverInfo: Hashable, Codable, Sendable {

    /// Cap absolu d'over par stat, en densité (toutes stats confondues).
    public static let densityCap: Int = 101

    public let kind: StatKind
    public let overValue: Int     // valeur au-dessus du max théorique (ex: 213 - 200 = 13)
    public let runeDensity: Int   // densité de la rune utilisée pour cet over (1/3/10)

    public init(kind: StatKind, overValue: Int, runeDensity: Int) {
        self.kind = kind
        self.overValue = overValue
        self.runeDensity = runeDensity
    }

    /// Densité d'over consommée (overValue × runeDensity, approximation).
    public var consumedDensity: Int {
        overValue * runeDensity
    }

    /// Vrai si on est au-dessus du cap d'over.
    public var isOverCap: Bool {
        consumedDensity >= Self.densityCap
    }
}
