import Foundation

/// Une stat lue sur un item : type, valeur courante, et range (min-max) éventuelle.
public struct Stat: Hashable, Codable, Sendable {
    public let kind: StatKind
    public let value: Int
    public let minValue: Int?
    public let maxValue: Int?

    public init(kind: StatKind, value: Int, minValue: Int? = nil, maxValue: Int? = nil) {
        self.kind = kind
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
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
