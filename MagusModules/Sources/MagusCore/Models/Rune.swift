import Foundation

/// Une rune de forgemagie : rang × stat ciblée.
public struct Rune: Hashable, Codable, Sendable {

    /// Rang de la rune. Les bonus listés sont indicatifs pour une stat
    /// "neutre" (ex: Force) — les vrais bonus varient légèrement selon la stat.
    /// La densité (poids) est la vraie mesure pertinente pour la FM.
    public enum Power: String, Codable, CaseIterable, Sendable {
        case base    // Rune de base — densité 1, bonus +1 (ex: Rune Fo)
        case pa      // Rune PA — densité 3, bonus +3 (ex: Rune Pa Fo)
        case ra      // Rune RA — densité 10, bonus +10 (ex: Rune Ra Fo)

        /// Densité (poids) standard de ce rang.
        public var density: Int {
            switch self {
            case .base: return 1
            case .pa: return 3
            case .ra: return 10
            }
        }

        /// Préfixe affiché dans le nom (ex: "Ra Fo" → "Ra").
        public var prefix: String {
            switch self {
            case .base: return ""
            case .pa: return "Pa"
            case .ra: return "Ra"
            }
        }
    }

    public let kind: StatKind
    public let power: Power

    public init(kind: StatKind, power: Power) {
        self.kind = kind
        self.power = power
    }

    /// Densité totale (= densité du rang). À l'avenir, pourrait être pondérée par la stat.
    public var density: Int { power.density }
}

/// Inventaire de runes : nombre disponible par (kind, power).
public struct RuneInventory: Hashable, Codable, Sendable {
    public private(set) var quantities: [Rune: Int]

    public init(quantities: [Rune: Int] = [:]) {
        self.quantities = quantities
    }

    public func quantity(of rune: Rune) -> Int {
        quantities[rune] ?? 0
    }

    public mutating func set(_ rune: Rune, quantity: Int) {
        if quantity <= 0 {
            quantities.removeValue(forKey: rune)
        } else {
            quantities[rune] = quantity
        }
    }

    public var totalCount: Int {
        quantities.values.reduce(0, +)
    }
}
