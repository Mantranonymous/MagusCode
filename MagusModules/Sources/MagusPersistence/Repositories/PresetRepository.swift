import Foundation
import GRDB
import MagusCommon
import MagusCore
import os

/// Stocke et récupère les StatsPreset persistés.
public struct PresetRepository: Sendable {

    private let dbQueue: DatabaseQueue
    private let logger = MagusLogger.persistence

    public init(database: DatabaseManager) {
        self.dbQueue = database.dbQueue
    }

    public func allPresets() throws -> [StatsPreset] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM stats_presets ORDER BY updated_at DESC")
            return try rows.map { try loadPreset(presetRow: $0, db: db) }
        }
    }

    public func presets(forItem itemSpecId: Int) throws -> [StatsPreset] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM stats_presets WHERE item_spec_id = ? ORDER BY updated_at DESC",
                arguments: [itemSpecId]
            )
            return try rows.map { try loadPreset(presetRow: $0, db: db) }
        }
    }

    public func preset(id: UUID) throws -> StatsPreset? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM stats_presets WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return try loadPreset(presetRow: row, db: db)
        }
    }

    public func save(_ preset: StatsPreset) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO stats_presets (id, name, scenario, item_spec_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    scenario = excluded.scenario,
                    item_spec_id = excluded.item_spec_id,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    preset.id.uuidString,
                    preset.name,
                    preset.scenario.rawValue,
                    preset.itemSpecId,
                    preset.createdAt,
                    preset.updatedAt
                ]
            )

            try db.execute(
                sql: "DELETE FROM stats_preset_targets WHERE preset_id = ?",
                arguments: [preset.id.uuidString]
            )

            for (kind, target) in preset.targets {
                try db.execute(
                    sql: """
                    INSERT INTO stats_preset_targets
                    (preset_id, characteristic_id, target, minimum, priority, enabled)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        preset.id.uuidString,
                        kind.characteristicId,
                        target.target,
                        target.minimum,
                        target.priority,
                        target.enabled ? 1 : 0
                    ]
                )
            }

            logger.debug("Preset \(preset.name, privacy: .public) saved (\(preset.targets.count) targets)")
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM stats_presets WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Helpers

    private func loadPreset(presetRow: Row, db: Database) throws -> StatsPreset {
        let idStr: String = presetRow["id"]
        let id = UUID(uuidString: idStr) ?? UUID()
        let name: String = presetRow["name"]
        let scenarioStr: String = presetRow["scenario"]
        let scenario = PresetScenario(rawValue: scenarioStr) ?? .jetParfait
        let itemSpecId: Int? = presetRow["item_spec_id"]
        let createdAt: Date = presetRow["created_at"]
        let updatedAt: Date = presetRow["updated_at"]

        let targetRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM stats_preset_targets WHERE preset_id = ?",
            arguments: [idStr]
        )
        var targets: [StatKind: StatTarget] = [:]
        for row in targetRows {
            let charId: Int = row["characteristic_id"]
            let targetValue: Int = row["target"]
            let minimum: Int? = row["minimum"]
            let priority: Int = row["priority"]
            let enabledRaw: Int = row["enabled"]
            targets[StatKind(characteristicId: charId)] = StatTarget(
                target: targetValue,
                minimum: minimum,
                priority: priority,
                enabled: enabledRaw != 0
            )
        }

        return StatsPreset(
            id: id,
            name: name,
            scenario: scenario,
            itemSpecId: itemSpecId,
            targets: targets,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
