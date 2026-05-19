import Foundation
import MagusCore

/// Parse la zone "Niveau métier" (ex: "Niveau 158 Forgemagie", "Forgemagie 158").
public struct JobLevelParser: Sendable {

    public init() {}

    public struct Output: Equatable, Sendable {
        public let level: Int?
        public let jobName: String?
    }

    public func parse(text: String) -> Output {
        let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var level: Int? = nil
        var jobName: String? = nil

        for line in lines {
            if level == nil, let n = OCRCorrection.firstInt(in: line), (1...200).contains(n) {
                level = n
            }
            // Détecte un nom de métier connu
            if jobName == nil {
                let lower = line.lowercased()
                for candidate in JobLevelParser.knownJobs where lower.contains(candidate.lowercased()) {
                    jobName = candidate
                    break
                }
            }
        }

        return Output(level: level, jobName: jobName)
    }

    /// Liste minimale de métiers — étendue dynamiquement plus tard.
    public static let knownJobs: [String] = [
        "Forgemagie", "Forgemage",
        "Cordomagie", "Cordomage",
        "Joaillomagie", "Joaillomage",
        "Sculptomagie", "Sculptomage",
        "Façonnage",
    ]
}
