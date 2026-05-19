import Foundation
import MagusCommon
import os

/// État courant d'une sync DofusDB en cours.
public struct SyncProgress: Equatable, Sendable {
    public let stage: Stage
    public let fetched: Int
    public let total: Int

    public enum Stage: String, Sendable {
        case idle
        case version
        case characteristics
        case itemTypes
        case effects
        case items
        case persisting
        case done
        case failed
    }

    public init(stage: Stage, fetched: Int = 0, total: Int = 0) {
        self.stage = stage
        self.fetched = fetched
        self.total = total
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(fetched) / Double(total))
    }
}

/// Type d'items à synchroniser pour Magus.
/// On limite aux items équipables mageables : amulette, anneau, ceinture, bottes,
/// cape, coiffe, bouclier, sac, trophée — pas les armes/consommables.
public enum SyncableItemType: Int, CaseIterable, Sendable {
    case amulette = 1
    case anneau = 9
    case ceinture = 10
    case bottes = 11
    // D'autres seront ajoutés après validation des typeId réels via l'API.

    public static var ids: [Int] { allCases.map(\.rawValue) }
}

public enum ReferenceSyncError: Error, Sendable {
    case alreadyRunning
    case fetchFailed(stage: SyncProgress.Stage, underlying: String)
    case persistenceFailed(underlying: String)
}

/// Orchestre le download des données DofusDB et leur stockage local.
public actor ReferenceDataSync {

    private let client: DofusDBClient
    private let repository: ReferenceRepository
    private let logger = MagusLogger.persistence
    private var isRunning = false

    /// Callback de progression (appelé sur un thread arbitraire).
    public typealias ProgressHandler = @Sendable (SyncProgress) -> Void

    public init(client: DofusDBClient, repository: ReferenceRepository) {
        self.client = client
        self.repository = repository
    }

    /// Lance une sync complète. Idempotent : si déjà en cours, lève une erreur.
    public func sync(progress: ProgressHandler? = nil) async throws {
        guard !isRunning else { throw ReferenceSyncError.alreadyRunning }
        isRunning = true
        defer { isRunning = false }

        let report: (SyncProgress) -> Void = { p in progress?(p) }

        // 1. Version
        report(SyncProgress(stage: .version))
        let version: String
        do { version = try await client.fetchVersion() }
        catch { throw ReferenceSyncError.fetchFailed(stage: .version, underlying: "\(error)") }
        logger.info("DofusDB version: \(version, privacy: .public)")

        // 2. Characteristics
        let chars: [DofusDBCharacteristic]
        do {
            chars = try await client.fetchAllCharacteristics { fetched, total in
                report(SyncProgress(stage: .characteristics, fetched: fetched, total: total))
            }
        } catch { throw ReferenceSyncError.fetchFailed(stage: .characteristics, underlying: "\(error)") }

        // 3. Item types
        let itemTypes: [DofusDBItemType]
        do {
            itemTypes = try await client.fetchAllItemTypes { fetched, total in
                report(SyncProgress(stage: .itemTypes, fetched: fetched, total: total))
            }
        } catch { throw ReferenceSyncError.fetchFailed(stage: .itemTypes, underlying: "\(error)") }

        // 4. Effects
        let effects: [DofusDBEffect]
        do {
            effects = try await client.fetchAllEffects { fetched, total in
                report(SyncProgress(stage: .effects, fetched: fetched, total: total))
            }
        } catch { throw ReferenceSyncError.fetchFailed(stage: .effects, underlying: "\(error)") }

        // 5. Items (filtrés sur les types mageables)
        let items: [DofusDBItem]
        do {
            items = try await client.fetchItems(typeIds: SyncableItemType.ids) { fetched, total in
                report(SyncProgress(stage: .items, fetched: fetched, total: total))
            }
        } catch { throw ReferenceSyncError.fetchFailed(stage: .items, underlying: "\(error)") }

        // 6. Persistence
        report(SyncProgress(stage: .persisting))
        do {
            try repository.saveCharacteristics(chars.map(mapCharacteristic))
            try repository.saveItemTypes(itemTypes.map(mapItemType))
            try repository.saveEffects(effects.map(mapEffect))

            var refItems: [RefItem] = []
            var refItemEffects: [RefItemEffect] = []
            for item in items {
                refItems.append(mapItem(item))
                for (i, e) in (item.possibleEffects ?? []).enumerated() {
                    refItemEffects.append(RefItemEffect(
                        itemId: item.id,
                        effectId: e.effectId,
                        order: e.order ?? i,
                        diceNum: e.diceNum,
                        diceSide: e.diceSide
                    ))
                }
            }
            try repository.saveItems(refItems, itemEffects: refItemEffects)

            try repository.setMeta(.dofusDBVersion, value: version)
            try repository.setMeta(.lastSyncAt, value: ISO8601DateFormatter().string(from: Date()))
        } catch { throw ReferenceSyncError.persistenceFailed(underlying: "\(error)") }

        logger.info("DofusDB sync done: \(chars.count) chars, \(itemTypes.count) types, \(effects.count) effects, \(items.count) items")
        report(SyncProgress(stage: .done))
    }

    /// Vérifie si une sync est nécessaire : pas de version locale, ou version différente.
    public func needsSync() throws -> Bool {
        let local = try repository.getMeta(.dofusDBVersion)
        guard local != nil else { return true }
        // On vérifie le age du dernier sync : > 7 jours = refresh
        if let lastSyncStr = try repository.getMeta(.lastSyncAt),
           let lastSync = ISO8601DateFormatter().date(from: lastSyncStr) {
            let age = Date().timeIntervalSince(lastSync)
            return age > 7 * 24 * 3600
        }
        return true
    }

    // MARK: - DTO → Repo mappers

    private func mapCharacteristic(_ c: DofusDBCharacteristic) -> RefCharacteristic {
        RefCharacteristic(
            id: c.id,
            keyword: c.keyword,
            nameFR: c.name.fr,
            nameEN: c.name.en,
            categoryId: c.categoryId,
            visible: c.visible ?? true
        )
    }

    private func mapItemType(_ t: DofusDBItemType) -> RefItemType {
        RefItemType(id: t.id, superTypeId: t.superTypeId, nameFR: t.name.fr)
    }

    private func mapEffect(_ e: DofusDBEffect) -> RefEffect {
        RefEffect(
            id: e.id,
            characteristicId: e.characteristic,
            descriptionFR: e.description.fr,
            descriptionEN: e.description.en,
            isInPercent: e.isInPercent ?? false,
            boost: e.boost ?? false
        )
    }

    private func mapItem(_ i: DofusDBItem) -> RefItem {
        RefItem(
            id: i.id,
            typeId: i.typeId,
            level: i.level,
            nameFR: i.name.fr,
            iconId: i.iconId,
            itemSetId: i.itemSetId
        )
    }
}
