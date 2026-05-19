import Foundation

/// Reliquat (puits) : densité de stats sortantes accumulée et disponible.
/// Concept central de la FM Dofus — voir mémoire `forgemagie-domain`.
///
/// La densité peut être fractionnaire (ex: 2.2) car les runes ont des poids
/// non-entiers selon la stat ciblée.
public struct Reliquat: Hashable, Codable, Sendable {
    public let density: Double

    public init(density: Double) {
        self.density = max(0, density)
    }

    public var isEmpty: Bool { density == 0 }
    public var hasCapacity: Bool { density > 0 }

    /// Peut-on poser une rune sans toucher aux stats de l'item ?
    public func canAbsorb(runeDensity: Double) -> Bool {
        density >= runeDensity
    }

    /// Reliquat après absorption d'une rune (typique en cas de SC).
    public func consuming(runeDensity: Double) -> Reliquat {
        Reliquat(density: max(0, density - runeDensity))
    }

    /// Reliquat après une perte (typique en cas de chute d'une grosse stat).
    public func gaining(lostDensity: Double) -> Reliquat {
        Reliquat(density: density + lostDensity)
    }

    /// Formatage compact pour l'UI ("2.2" ou "27").
    public var formatted: String {
        if density.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", density)
        }
        return String(format: "%.1f", density)
    }
}
