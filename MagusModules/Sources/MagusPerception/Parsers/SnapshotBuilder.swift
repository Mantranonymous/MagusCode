import Foundation
import MagusCommon
import MagusCore
import os

/// Transforme un RawOCRSnapshot (texte brut par région) en GameStateSnapshot typé,
/// en appliquant les parsers appropriés à chaque région.
public struct SnapshotBuilder: Sendable {

    private let dictionary: StatDictionary
    private let logger = MagusLogger.perception

    public init(dictionary: StatDictionary) {
        self.dictionary = dictionary
    }

    public func build(from raw: RawOCRSnapshot) -> GameStateSnapshot {
        let statParser = StatLineParser(dictionary: dictionary)
        let historyParser = HistoryParser(dictionary: dictionary)
        let reliquatParser = ReliquatParser()
        let jobParser = JobLevelParser()

        var stats: [Stat] = []
        var history: [MageHistoryEntry] = []
        var reliquat: Reliquat? = nil
        var jobLevel: Int? = nil
        var jobName: String? = nil

        // Stats : on regroupe par ligne visuelle (Y proches) pour reconstituer les rows
        // de la table FM. Vision sépare souvent les colonnes en observations distinctes.
        if let statsRegion = raw.results[.stats] {
            let statsText = statsRegion.rowGroupedText
            stats = statParser.parseAll(text: statsText)
        }
        if let historyText = raw.results[.history]?.joinedText {
            history = historyParser.parse(text: historyText)
        }
        if let reliquatText = raw.results[.reliquat]?.joinedText {
            reliquat = reliquatParser.parse(text: reliquatText)
        }
        if let jobText = raw.results[.jobLevel]?.joinedText {
            let out = jobParser.parse(text: jobText)
            jobLevel = out.level
            jobName = out.jobName
        }

        let item: Item? = stats.isEmpty ? nil : Item(name: "Item courant", stats: stats)

        let snapshot = GameStateSnapshot(
            timestamp: raw.frameTimestamp,
            item: item,
            history: history,
            reliquat: reliquat,
            jobLevel: jobLevel,
            jobName: jobName
        )

        logger.debug("Snapshot built: \(stats.count) stats, \(history.count) history, reliquat=\(String(describing: reliquat)), job=\(String(describing: jobLevel))")
        return snapshot
    }
}
