import Foundation
import GRDB
import MagusCommon
import MagusPersistence
import os

/// Représentation locale d'une caractéristique (stat) — alimentée par DofusDB.
public struct RefCharacteristic: Hashable, Sendable {
    public let id: Int
    public let keyword: String?
    public let nameFR: String?
    public let nameEN: String?
    public let categoryId: Int?
    public let visible: Bool
}

public struct RefItemType: Hashable, Sendable {
    public let id: Int
    public let superTypeId: Int?
    public let nameFR: String?
}

public struct RefEffect: Hashable, Sendable {
    public let id: Int
    public let characteristicId: Int?
    public let descriptionFR: String?
    public let descriptionEN: String?
    public let isInPercent: Bool
    public let boost: Bool
}

public struct RefItem: Hashable, Sendable {
    public let id: Int
    public let typeId: Int?
    public let level: Int?
    public let nameFR: String?
    public let iconId: Int?
    public let itemSetId: Int?
}

public struct RefItemEffect: Hashable, Sendable {
    public let itemId: Int
    public let effectId: Int
    public let order: Int
    public let diceNum: Double?
    public let diceSide: Double?
}

public enum ReferenceMetaKey: String, Sendable {
    case dofusDBVersion = "dofusdb_version"
    case lastSyncAt = "last_sync_at"
}

/// Repository pour les données de référence DofusDB stockées localement.
public struct ReferenceRepository: Sendable {

    private let dbQueue: DatabaseQueue
    private let logger = MagusLogger.persistence

    public init(database: DatabaseManager) {
        self.dbQueue = database.dbQueue
    }

    // MARK: - Meta

    public func getMeta(_ key: ReferenceMetaKey) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM ref_meta WHERE key = ?", arguments: [key.rawValue])
        }
    }

    public func setMeta(_ key: ReferenceMetaKey, value: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO ref_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key.rawValue, value]
            )
        }
    }

    // MARK: - Characteristics

    public func saveCharacteristics(_ items: [RefCharacteristic]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM ref_characteristics")
            for c in items {
                try db.execute(
                    sql: "INSERT INTO ref_characteristics (id, keyword, name_fr, name_en, category_id, visible) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [c.id, c.keyword, c.nameFR, c.nameEN, c.categoryId, c.visible ? 1 : 0]
                )
            }
        }
    }

    public func allCharacteristics() throws -> [RefCharacteristic] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM ref_characteristics ORDER BY id").map(rowToCharacteristic)
        }
    }

    public func characteristic(id: Int) throws -> RefCharacteristic? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM ref_characteristics WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return rowToCharacteristic(row)
        }
    }

    public func characteristic(matchingFRName name: String) throws -> RefCharacteristic? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM ref_characteristics WHERE LOWER(name_fr) = LOWER(?) LIMIT 1",
                arguments: [name]
            ) else { return nil }
            return rowToCharacteristic(row)
        }
    }

    // MARK: - Item types

    public func saveItemTypes(_ types: [RefItemType]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM ref_item_types")
            for t in types {
                try db.execute(
                    sql: "INSERT INTO ref_item_types (id, super_type_id, name_fr) VALUES (?, ?, ?)",
                    arguments: [t.id, t.superTypeId, t.nameFR]
                )
            }
        }
    }

    public func allItemTypes() throws -> [RefItemType] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM ref_item_types ORDER BY id").map(rowToItemType)
        }
    }

    // MARK: - Effects

    public func saveEffects(_ effects: [RefEffect]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM ref_effects")
            for e in effects {
                try db.execute(
                    sql: "INSERT INTO ref_effects (id, characteristic_id, description_fr, description_en, is_in_percent, boost) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [e.id, e.characteristicId, e.descriptionFR, e.descriptionEN, e.isInPercent ? 1 : 0, e.boost ? 1 : 0]
                )
            }
        }
    }

    public func effect(id: Int) throws -> RefEffect? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM ref_effects WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return rowToEffect(row)
        }
    }

    // MARK: - Items

    public func saveItems(_ items: [RefItem], itemEffects: [RefItemEffect]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM ref_item_effects")
            try db.execute(sql: "DELETE FROM ref_items")
            for it in items {
                try db.execute(
                    sql: "INSERT INTO ref_items (id, type_id, level, name_fr, name_en, icon_id, item_set_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arguments: [it.id, it.typeId, it.level, it.nameFR, nil, it.iconId, it.itemSetId]
                )
            }
            for e in itemEffects {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO ref_item_effects (item_id, effect_id, order_idx, dice_num, dice_side) VALUES (?, ?, ?, ?, ?)",
                    arguments: [e.itemId, e.effectId, e.order, e.diceNum, e.diceSide]
                )
            }
        }
    }

    public func itemCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ref_items") ?? 0
        }
    }

    public func item(matchingFRName name: String) throws -> RefItem? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM ref_items WHERE LOWER(name_fr) = LOWER(?) LIMIT 1",
                arguments: [name]
            ) else { return nil }
            return rowToItem(row)
        }
    }

    public func itemEffects(itemId: Int) throws -> [RefItemEffect] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM ref_item_effects WHERE item_id = ? ORDER BY order_idx",
                arguments: [itemId]
            ).map(rowToItemEffect)
        }
    }

    public func characteristicCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ref_characteristics") ?? 0
        }
    }

    public func effectCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ref_effects") ?? 0
        }
    }

    // MARK: - Row mappers

    private func rowToCharacteristic(_ r: Row) -> RefCharacteristic {
        let id: Int = r["id"]
        let visible: Int = r["visible"]
        return RefCharacteristic(
            id: id,
            keyword: r["keyword"],
            nameFR: r["name_fr"],
            nameEN: r["name_en"],
            categoryId: r["category_id"],
            visible: visible != 0
        )
    }

    private func rowToItemType(_ r: Row) -> RefItemType {
        let id: Int = r["id"]
        return RefItemType(
            id: id,
            superTypeId: r["super_type_id"],
            nameFR: r["name_fr"]
        )
    }

    private func rowToEffect(_ r: Row) -> RefEffect {
        let id: Int = r["id"]
        let isPct: Int = r["is_in_percent"]
        let boost: Int = r["boost"]
        return RefEffect(
            id: id,
            characteristicId: r["characteristic_id"],
            descriptionFR: r["description_fr"],
            descriptionEN: r["description_en"],
            isInPercent: isPct != 0,
            boost: boost != 0
        )
    }

    private func rowToItem(_ r: Row) -> RefItem {
        let id: Int = r["id"]
        return RefItem(
            id: id,
            typeId: r["type_id"],
            level: r["level"],
            nameFR: r["name_fr"],
            iconId: r["icon_id"],
            itemSetId: r["item_set_id"]
        )
    }

    private func rowToItemEffect(_ r: Row) -> RefItemEffect {
        let itemId: Int = r["item_id"]
        let effectId: Int = r["effect_id"]
        let order: Int = r["order_idx"]
        return RefItemEffect(
            itemId: itemId,
            effectId: effectId,
            order: order,
            diceNum: r["dice_num"],
            diceSide: r["dice_side"]
        )
    }
}
