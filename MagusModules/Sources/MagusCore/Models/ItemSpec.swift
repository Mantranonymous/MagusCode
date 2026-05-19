import Foundation

/// "Spec" canonique d'un item, alimentée par DofusDB (table ref_items + ref_item_effects).
/// Contrairement à `Item` qui représente l'état courant lu via OCR, `ItemSpec` est statique
/// et nous dit exactement quelles stats peuvent figurer sur l'item et leurs ranges théoriques.
public struct ItemSpec: Hashable, Codable, Sendable, Identifiable {
    public let id: Int               // DofusDB item ID
    public let name: String
    public let level: Int
    public let typeId: Int?
    public let typeName: String?
    public let stats: [StatSpec]

    public init(
        id: Int,
        name: String,
        level: Int,
        typeId: Int? = nil,
        typeName: String? = nil,
        stats: [StatSpec] = []
    ) {
        self.id = id
        self.name = name
        self.level = level
        self.typeId = typeId
        self.typeName = typeName
        self.stats = stats
    }

    public var metier: Metier? {
        typeId.flatMap { Metier.from(itemTypeId: $0) }
    }

    /// Retourne la spec d'une stat si elle est dans les possibleEffects.
    public func spec(matching kind: StatKind) -> StatSpec? {
        stats.first { $0.kind == kind }
    }

    public var minLevelRequired: Int { level }
}

/// Spec d'une stat sur un item : qu'est-ce qu'elle peut donner au min et au max.
public struct StatSpec: Hashable, Codable, Sendable {
    public let kind: StatKind
    public let displayName: String   // FR depuis DofusDB
    public let minValue: Int         // diceNum
    public let maxValue: Int         // diceSide
    public let order: Int            // ordre dans la liste pour conserver la disposition

    public init(kind: StatKind, displayName: String, minValue: Int, maxValue: Int, order: Int = 0) {
        self.kind = kind
        self.displayName = displayName
        self.minValue = minValue
        self.maxValue = maxValue
        self.order = order
    }

    /// Largeur de la range (utile pour pondérer la difficulté).
    public var rangeSpan: Int { maxValue - minValue }

    /// Vrai si la stat a un range pertinent (les stats triviales comme PA/PM 1/1 ne sont pas vraiment mageables).
    public var isMageable: Bool { maxValue > minValue }
}
