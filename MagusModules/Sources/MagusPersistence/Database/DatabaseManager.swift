import Foundation
import GRDB
import MagusCommon
import os

/// Gère la base de données SQLite locale via GRDB.
/// Stockée dans Application Support de l'utilisateur.
public final class DatabaseManager: @unchecked Sendable {

    public let dbQueue: DatabaseQueue
    private let logger = MagusLogger.persistence

    /// Crée un DatabaseManager pointant vers la DB Magus standard (Application Support).
    public static func makeDefault() throws -> DatabaseManager {
        let url = try defaultDatabaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: url.path)
        return try DatabaseManager(dbQueue: queue)
    }

    /// Crée un DatabaseManager en mémoire pour les tests.
    public static func makeInMemory() throws -> DatabaseManager {
        let queue = try DatabaseQueue()
        return try DatabaseManager(dbQueue: queue)
    }

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
        logger.info("DatabaseManager initialized at \(dbQueue.path, privacy: .public)")
    }

    private static func defaultDatabaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Magus/magus.sqlite")
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_resolution_profiles") { db in
            try db.create(table: "resolution_profiles") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("reference_width", .double).notNull()
                t.column("reference_height", .double).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "regions") { t in
                t.column("id", .text).primaryKey()
                t.column("profile_id", .text)
                    .notNull()
                    .references("resolution_profiles", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("x", .double).notNull()
                t.column("y", .double).notNull()
                t.column("width", .double).notNull()
                t.column("height", .double).notNull()
                t.uniqueKey(["profile_id", "kind"])
            }
        }

        migrator.registerMigration("v2_dofusdb_reference") { db in
            try db.create(table: "ref_meta") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }

            try db.create(table: "ref_characteristics") { t in
                t.column("id", .integer).primaryKey()
                t.column("keyword", .text)
                t.column("name_fr", .text)
                t.column("name_en", .text)
                t.column("category_id", .integer)
                t.column("visible", .integer).notNull().defaults(to: 1)
            }

            try db.create(table: "ref_item_types") { t in
                t.column("id", .integer).primaryKey()
                t.column("super_type_id", .integer)
                t.column("name_fr", .text)
                t.column("name_en", .text)
            }

            try db.create(table: "ref_effects") { t in
                t.column("id", .integer).primaryKey()
                t.column("characteristic_id", .integer)
                t.column("description_fr", .text)
                t.column("description_en", .text)
                t.column("is_in_percent", .integer).notNull().defaults(to: 0)
                t.column("boost", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_ref_effects_char", on: "ref_effects", columns: ["characteristic_id"])

            try db.create(table: "ref_items") { t in
                t.column("id", .integer).primaryKey()
                t.column("type_id", .integer)
                t.column("level", .integer)
                t.column("name_fr", .text)
                t.column("name_en", .text)
                t.column("icon_id", .integer)
                t.column("item_set_id", .integer)
            }
            try db.create(index: "idx_ref_items_type", on: "ref_items", columns: ["type_id"])
            try db.create(index: "idx_ref_items_name_fr", on: "ref_items", columns: ["name_fr"])

            try db.create(table: "ref_item_effects") { t in
                t.column("item_id", .integer).notNull()
                t.column("effect_id", .integer).notNull()
                t.column("order_idx", .integer).notNull().defaults(to: 0)
                t.column("dice_num", .double)
                t.column("dice_side", .double)
                t.column("base_effect_id", .integer)
                t.primaryKey(["item_id", "effect_id", "order_idx"])
            }
            try db.create(index: "idx_ref_item_effects_item", on: "ref_item_effects", columns: ["item_id"])
        }

        return migrator
    }
}
