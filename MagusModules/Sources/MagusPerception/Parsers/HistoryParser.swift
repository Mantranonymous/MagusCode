import Foundation
import MagusCore

/// Parse l'historique des combines. Chaque ligne ressemble typiquement à :
///   "+ 1 Vitalité"   (gain)
///   "- 2 Force"      (perte)
///   "Échec"          (combine landed sans gain)
///
/// La structure exacte dépend de la version du jeu, on reste tolérant.
public struct HistoryParser: Sendable {

    private let dictionary: StatDictionary

    public init(dictionary: StatDictionary) {
        self.dictionary = dictionary
    }

    public func parse(text: String) -> [MageHistoryEntry] {
        text.split(separator: "\n").compactMap { parseLine(String($0)) }
    }

    public func parseLine(_ line: String) -> MageHistoryEntry? {
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        let lower = clean.lowercased()

        // Détection d'échec explicite
        if lower.contains("échec") || lower.contains("echec") || lower.contains("raté") {
            return MageHistoryEntry(result: .failure, kind: .unknown, raw: clean)
        }

        // Pattern : "+ N Nom de stat" ou "- N Nom de stat"
        let isPositive = clean.hasPrefix("+") || lower.contains("gain")
        let isNegative = clean.hasPrefix("-") || lower.contains("perd")

        let numbers = extractNumbers(clean)
        guard let firstNumber = numbers.first else {
            return nil
        }
        let delta = isNegative ? -abs(firstNumber) : (isPositive ? abs(firstNumber) : firstNumber)

        let statName = extractStatName(line: clean)
        let kind = statName.flatMap { dictionary.lookupFuzzy($0) }

        let result: MageHistoryEntry.Result =
            delta > 0 ? .success : (delta < 0 ? .failure : .neutral)

        return MageHistoryEntry(
            result: result,
            kind: .unknown,
            targetStat: kind,
            delta: delta,
            raw: clean
        )
    }

    // MARK: - Helpers

    private func extractNumbers(_ line: String) -> [Int] {
        var result: [Int] = []
        var current = ""
        for c in line {
            if c.isNumber { current.append(c) }
            else if !current.isEmpty {
                if let v = Int(current) { result.append(v) }
                current = ""
            }
        }
        if !current.isEmpty, let v = Int(current) { result.append(v) }
        return result
    }

    private func extractStatName(line: String) -> String? {
        let tokens = line.split(whereSeparator: { $0.isWhitespace || $0 == ":" }).map(String.init)
        let words = tokens.filter { tok in
            !tok.allSatisfy(\.isNumber) && !tok.allSatisfy({ "()+-/".contains($0) })
        }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
