import Foundation
import MagusCore

/// Parse une "ligne de stat" comme :
///   "Vitalité 180 (150-200)"
///   "+ 87 Force"
///   "PA 11 (10-12)"
///   "Sagesse 42"
///
/// Retourne nil si la ligne ne ressemble pas à une stat exploitable.
public struct StatLineParser: Sendable {

    private let dictionary: StatDictionary

    public init(dictionary: StatDictionary) {
        self.dictionary = dictionary
    }

    /// Parse une seule ligne. Si la ligne contient plusieurs stats, on prend la première.
    public func parse(line: String) -> Stat? {
        let cleaned = clean(line)
        guard !cleaned.isEmpty else { return nil }

        // Pattern 1 : "Vitalité 180 (150-200)"
        // Pattern 2 : "+ 87 Force"
        // Pattern 3 : "Vitalité 180"

        // On extrait : tokens
        let tokens = tokenize(cleaned)
        guard !tokens.isEmpty else { return nil }

        // Trouve la valeur principale (premier int) et la range éventuelle
        let numbers = extractNumbers(cleaned)
        guard let value = numbers.first else { return nil }

        // La range est entre parenthèses : (min-max) ou (min/max)
        let range = extractParenRange(cleaned)

        // Le nom de stat = mots non-numériques
        let nameCandidate = extractStatName(tokens: tokens)
        guard let name = nameCandidate else { return nil }

        guard let kind = dictionary.lookupFuzzy(name) else { return nil }

        return Stat(
            kind: kind,
            value: value,
            minValue: range?.lowerBound,
            maxValue: range?.upperBound
        )
    }

    /// Parse plusieurs lignes (la zone Stats contient typiquement N lignes).
    public func parseAll(text: String) -> [Stat] {
        text.split(separator: "\n").compactMap { parse(line: String($0)) }
    }

    // MARK: - Helpers

    private func clean(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(_ line: String) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace || $0 == ":" }).map(String.init)
    }

    private func extractNumbers(_ line: String) -> [Int] {
        var result: [Int] = []
        var current = ""
        var negative = false
        for c in line {
            if c.isNumber {
                current.append(c)
            } else {
                if !current.isEmpty {
                    if let v = Int(current) {
                        result.append(negative ? -v : v)
                    }
                    current = ""
                }
                negative = (c == "-")
            }
        }
        if !current.isEmpty, let v = Int(current) {
            result.append(negative ? -v : v)
        }
        return result
    }

    private func extractParenRange(_ line: String) -> ClosedRange<Int>? {
        // Match "(123-456)" ou "(123/456)" ou "(123 à 456)"
        guard let openIdx = line.firstIndex(of: "("),
              let closeIdx = line.firstIndex(of: ")"),
              openIdx < closeIdx else { return nil }
        let inside = String(line[line.index(after: openIdx)..<closeIdx])
        let parts = inside.split(whereSeparator: { "-/à ".contains($0) })
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        let low = min(numbers[0], numbers[1])
        let high = max(numbers[0], numbers[1])
        return low...high
    }

    private func extractStatName(tokens: [String]) -> String? {
        // Prend les tokens de tête (avant le premier token contenant chiffre ou paren).
        // Ex: ["Vitalité", "180", "(150-200)"] → ["Vitalité"]
        // Ex: ["+", "87", "Force"] → [] (sera géré différemment côté history)
        var words: [String] = []
        for tok in tokens {
            if tok.contains(where: { $0.isNumber || "()+-/".contains($0) }) {
                break
            }
            words.append(tok)
        }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
