import Foundation
import MagusCore

/// Service d'export/import de presets au format JSON `.magus`.
public struct PresetIO: Sendable {

    /// Wrapper exportable : preset + config + metadata.
    public struct ExportedPreset: Codable, Sendable {
        public let format: String
        public let version: Int
        public let exportedAt: Date
        public let stats: StatsPreset
        public let config: ConfigPreset

        public init(stats: StatsPreset, config: ConfigPreset) {
            self.format = "magus.preset"
            self.version = 1
            self.exportedAt = Date()
            self.stats = stats
            self.config = config
        }
    }

    public init() {}

    /// Encode en JSON pretty-printed.
    public func encode(stats: StatsPreset, config: ConfigPreset) throws -> Data {
        let payload = ExportedPreset(stats: stats, config: config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Décode depuis JSON. Tolère les formats sans `format` field (legacy).
    public func decode(_ data: Data) throws -> ExportedPreset {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportedPreset.self, from: data)
    }

    /// Nom de fichier safe à partir du nom du preset.
    public func suggestedFilename(for preset: StatsPreset) -> String {
        let safe = preset.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
        return "\(safe).magus.json"
    }
}
