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
        let sinkParser = SinkParser()
        let jobParser = JobLevelParser()

        var stats: [Stat] = []
        var history: [MageHistoryEntry] = []
        var sink: Sink? = nil
        var jobLevel: Int? = nil
        var jobName: String? = nil

        if let statsText = raw.results[.stats]?.joinedText {
            stats = statParser.parseAll(text: statsText)
        }
        if let historyText = raw.results[.history]?.joinedText {
            history = historyParser.parse(text: historyText)
        }
        if let sinkText = raw.results[.sink]?.joinedText {
            sink = sinkParser.parse(text: sinkText)
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
            sink: sink,
            jobLevel: jobLevel,
            jobName: jobName
        )

        logger.debug("Snapshot built: \(stats.count) stats, \(history.count) history, sink=\(String(describing: sink)), job=\(String(describing: jobLevel))")
        return snapshot
    }
}
