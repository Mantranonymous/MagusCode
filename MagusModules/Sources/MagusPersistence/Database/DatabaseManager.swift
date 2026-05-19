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

        return migrator
    }
}
