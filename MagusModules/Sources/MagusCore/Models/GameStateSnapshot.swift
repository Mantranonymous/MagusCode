import Foundation

/// Snapshot complet de l'état de la session forgemagie à un instant T.
/// Résultat du pipeline : OCR brut → parsers → ce type.
public struct GameStateSnapshot: Hashable, Codable, Sendable {
    public let timestamp: Date
    public let item: Item?
    public let history: [MageHistoryEntry]
    public let reliquat: Reliquat?
    public let jobLevel: Int?
    public let jobName: String?

    public init(
        timestamp: Date = Date(),
        item: Item? = nil,
        history: [MageHistoryEntry] = [],
        reliquat: Reliquat? = nil,
        jobLevel: Int? = nil,
        jobName: String? = nil
    ) {
        self.timestamp = timestamp
        self.item = item
        self.history = history
        self.reliquat = reliquat
        self.jobLevel = jobLevel
        self.jobName = jobName
    }

    public var hasItem: Bool { item != nil }
    public var hasReliquat: Bool { reliquat?.hasCapacity == true }
    public var lastCombine: MageHistoryEntry? { history.last }
}
