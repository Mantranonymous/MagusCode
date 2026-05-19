import Foundation
import GRDB
import MagusCommon
import MagusCore
import os

/// Stocke et récupère les profils de calibration (ResolutionProfile) depuis la DB.
public struct RegionRepository: Sendable {

    private let dbQueue: DatabaseQueue
    private let logger = MagusLogger.persistence

    public init(database: DatabaseManager) {
        self.dbQueue = database.dbQueue
    }

    // MARK: - Read

    public func allProfiles() throws -> [ResolutionProfile] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM resolution_profiles ORDER BY updated_at DESC")
            return try rows.map { try loadProfile(profileRow: $0, db: db) }
        }
    }

    public func profile(id: UUID) throws -> ResolutionProfile? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM resolution_profiles WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return try loadProfile(profileRow: row, db: db)
        }
    }

    // MARK: - Write

    public func save(_ profile: ResolutionProfile) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO resolution_profiles (id, name, reference_width, reference_height, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    reference_width = excluded.reference_width,
                    reference_height = excluded.reference_height,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    profile.id.uuidString,
                    profile.name,
                    profile.referenceWidth,
                    profile.referenceHeight,
                    profile.createdAt,
                    profile.updatedAt
                ]
            )

            // Replace regions (delete-and-insert pour simplicité)
            try db.execute(
                sql: "DELETE FROM regions WHERE profile_id = ?",
                arguments: [profile.id.uuidString]
            )

            for region in profile.regions.values {
                try db.execute(
                    sql: """
                    INSERT INTO regions (id, profile_id, kind, x, y, width, height)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        region.id.uuidString,
                        profile.id.uuidString,
                        region.kind.rawValue,
                        region.bounds.x,
                        region.bounds.y,
                        region.bounds.width,
                        region.bounds.height
                    ]
                )
            }

            logger.debug("Profile \(profile.name, privacy: .public) saved with \(profile.regions.count) regions")
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM resolution_profiles WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Helpers

    private func loadProfile(profileRow: Row, db: Database) throws -> ResolutionProfile {
        let id = UUID(uuidString: profileRow["id"]) ?? UUID()
        let regionRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM regions WHERE profile_id = ?",
            arguments: [id.uuidString]
        )

        var regions: [RegionKind: Region] = [:]
        for row in regionRows {
            guard
                let kindStr: String = row["kind"],
                let kind = RegionKind(rawValue: kindStr),
                let regionIDStr: String = row["id"],
                let regionID = UUID(uuidString: regionIDStr)
            else { continue }

            let x: Double = row["x"]
            let y: Double = row["y"]
            let w: Double = row["width"]
            let h: Double = row["height"]
            let bounds = NormalizedRect(x: x, y: y, width: w, height: h)
            regions[kind] = Region(id: regionID, kind: kind, bounds: bounds)
        }

        let refWidth: Double = profileRow["reference_width"]
        let refHeight: Double = profileRow["reference_height"]
        let name: String = profileRow["name"]
        let createdAt: Date = profileRow["created_at"]
        let updatedAt: Date = profileRow["updated_at"]

        return ResolutionProfile(
            id: id,
            name: name,
            referenceSize: CGSize(width: refWidth, height: refHeight),
            regions: regions,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
