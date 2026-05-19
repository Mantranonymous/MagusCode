import Foundation

/// Une rune de forgemagie : type de power × stat ciblée.
public struct Rune: Hashable, Codable, Sendable {

    /// Force de la rune (SM = Petite, Ra = standard, Pa = Puissante).
    public enum Power: String, Codable, CaseIterable, Sendable {
        case sm    // Petite (faible gain, peu de sink)
        case ra    // Standard
        case pa    // Puissante (gros gain, beaucoup de sink)
    }

    public let kind: StatKind
    public let power: Power

    public init(kind: StatKind, power: Power) {
        self.kind = kind
        self.power = power
    }
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
