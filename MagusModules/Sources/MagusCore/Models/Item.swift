import Foundation

/// Représente l'item posé sur l'établi (avec son état courant).
public struct Item: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    /// ID DofusDB si l'item a été reconnu via son nom.
    public let referenceItemId: Int?
    public var name: String
    public var level: Int?
    public var typeId: Int?
    public var stats: [Stat]
    public var exos: [Pute]

    public init(
        id: UUID = UUID(),
        referenceItemId: Int? = nil,
        name: String,
        level: Int? = nil,
        typeId: Int? = nil,
        stats: [Stat] = [],
        exos: [Pute] = []
    ) {
        self.id = id
        self.referenceItemId = referenceItemId
        self.name = name
        self.level = level
        self.typeId = typeId
        self.stats = stats
        self.exos = exos
    }

    public func stat(matching kind: StatKind) -> Stat? {
        stats.first { $0.kind == kind }
    }
}
