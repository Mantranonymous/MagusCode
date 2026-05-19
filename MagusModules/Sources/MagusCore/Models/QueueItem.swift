import Foundation

/// Un item dans la file d'attente FM batch.
public struct QueueItem: Hashable, Codable, Sendable, Identifiable {

    public enum Status: String, Codable, Sendable {
        case pending     // pas encore traité
        case current     // en cours de traitement
        case done        // fini avec succès
        case skipped     // sauté (erreur, safety, etc.)
    }

    public let id: UUID
    public let itemSpecId: Int
    public let itemName: String
    public let presetId: UUID
    public let presetName: String
    public var status: Status
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        itemSpecId: Int,
        itemName: String,
        presetId: UUID,
        presetName: String,
        status: Status = .pending,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.itemSpecId = itemSpecId
        self.itemName = itemName
        self.presetId = presetId
        self.presetName = presetName
        self.status = status
        self.addedAt = addedAt
    }
}
