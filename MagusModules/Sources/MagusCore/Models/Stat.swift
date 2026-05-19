import Foundation

/// Compteur de runes disponibles dans l'inventaire pour une stat donnée,
/// tel que lu dans les colonnes Pa/Ra de la stats table Dofus 3.
public struct StatRuneAvailability: Hashable, Codable, Sendable {
    public let baseCount: Int    // colonne "Modif." (souvent vide en pratique)
    public let paCount: Int
    public let raCount: Int

    public init(baseCount: Int = 0, paCount: Int = 0, raCount: Int = 0) {
        self.baseCount = baseCount
        self.paCount = paCount
        self.raCount = raCount
    }

    public var hasAny: Bool { baseCount > 0 || paCount > 0 || raCount > 0 }
}

/// Une stat lue sur un item : type, valeur courante, range, et runes dispos.
public struct Stat: Hashable, Codable, Sendable {
    public let kind: StatKind
    public let value: Int
    public let minValue: Int?
    public let maxValue: Int?
    public let availability: StatRuneAvailability?

    public init(
        kind: StatKind,
        value: Int,
        minValue: Int? = nil,
        maxValue: Int? = nil,
        availability: StatRuneAvailability? = nil
    ) {
        self.kind = kind
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.availability = availability
    }

    public var distanceToMax: Int? {
        guard let max = maxValue else { return nil }
        return max - value
    }

    public var distanceToMin: Int? {
        guard let min = minValue else { return nil }
        return value - min
    }

    public var isAtMax: Bool {
        guard let max = maxValue else { return false }
        return value >= max
    }

    public var isAtMin: Bool {
        guard let min = minValue else { return false }
        return value <= min
    }

    /// % de progression entre min et max (0...1). nil si pas de range.
    public var rangeProgress: Double? {
        guard let min = minValue, let max = maxValue, max > min else { return nil }
        return Double(value - min) / Double(max - min)
    }
}
