import Foundation
import MagusCore

/// Parse une ligne de la stats table Dofus 3. Formats supportés :
///
/// **Format Dofus 3 (colonnes)** :
///   `"151 200 208 Vitalité 238"`          → Min Max Value Name [extras Ra/Pa]
///   `"26 35 35 Intelligence 152 41"`       → ... Pa=152 Ra=41
///   `"26 35 34 Sagesse 875"`               → ... Ra=875
///
/// **Format simple (ancien / OCR partiel)** :
///   `"Vitalité 180 (150-200)"`             → name value (min-max)
///   `"+ 87 Force"`                         → +N Name
///   `"Vitalité 180"`                       → name value
///
/// Retourne nil si la ligne ne ressemble à aucune stat exploitable.
public struct StatLineParser: Sendable {

    private let dictionary: StatDictionary

    public init(dictionary: StatDictionary) {
        self.dictionary = dictionary
    }

    /// Parse une seule ligne. Choisit le format selon le nombre de leading numbers :
    /// 3+ leading numbers → format colonnes uniquement (strict).
    /// Sinon → format simple.
    public func parse(line: String) -> Stat? {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let tokens = tokenize(cleaned)
        let leadingNumCount = countLeadingNumbers(in: tokens)

        if leadingNumCount >= 3 {
            return parseColumnsFormat(line: cleaned, tokens: tokens)
        }
        return parseSimpleFormat(line: cleaned)
    }

    private func countLeadingNumbers(in tokens: [String]) -> Int {
        var count = 0
        for tok in tokens {
            if parseInt(tok) != nil {
                count += 1
            } else if isWordToken(tok) {
                break
            }
        }
        return count
    }

    /// Parse plusieurs lignes (la zone Stats contient typiquement N lignes).
    public func parseAll(text: String) -> [Stat] {
        text.split(separator: "\n").compactMap { parse(line: String($0)) }
    }

    // MARK: - Format colonnes Dofus 3

    /// Pattern attendu : `<min> <max> <value> <statName> [<modif>] [<pa>] [<ra>]`
    /// Heuristique : si on a au moins 3 nombres avant le nom et le nom est connu, c'est ce format.
    private func parseColumnsFormat(line: String, tokens: [String]) -> Stat? {
        guard tokens.count >= 4 else { return nil }

        // Sépare les tokens en groupes : numéros de tête, nom, numéros de queue
        var leadingNumbers: [Int] = []
        var nameTokens: [String] = []
        var trailingNumbers: [Int] = []
        var sawName = false

        for tok in tokens {
            if let n = parseInt(tok) {
                if sawName {
                    trailingNumbers.append(n)
                } else {
                    leadingNumbers.append(n)
                }
            } else if isWordToken(tok) {
                sawName = true
                nameTokens.append(tok)
            } else {
                // Ponctuation isolée → ignore
                if sawName, !nameTokens.isEmpty {
                    // si on a vu le nom, une ponctuation isolée n'arrête pas la collection
                }
            }
        }

        // Le format colonnes a au minimum 3 nombres de tête (min, max, value)
        guard leadingNumbers.count >= 3, !nameTokens.isEmpty else { return nil }

        let minV = leadingNumbers[0]
        let maxV = leadingNumbers[1]
        let value = leadingNumbers[2]
        let name = nameTokens.joined(separator: " ")

        // Sanity checks : min <= max et value plausible (incluant over)
        guard minV <= maxV, minV >= 0, maxV <= 100_000 else { return nil }

        // Présence de "%" → distingue résistance % vs fixe (et autres stats %)
        let hasPercent = line.contains("%")
        let nameForLookup = hasPercent ? "\(name) %" : name
        guard let kind = dictionary.lookupFuzzy(nameForLookup) ?? dictionary.lookupFuzzy(name) else {
            return nil
        }

        // Les trailing numbers : on tente l'interprétation [modif?, pa?, ra?]
        let availability = makeAvailability(from: trailingNumbers)

        return Stat(
            kind: kind,
            value: value,
            minValue: minV,
            maxValue: maxV,
            availability: availability
        )
    }

    private func makeAvailability(from numbers: [Int]) -> StatRuneAvailability? {
        guard !numbers.isEmpty else { return nil }
        switch numbers.count {
        case 1: return StatRuneAvailability(baseCount: 0, paCount: 0, raCount: numbers[0])
        case 2: return StatRuneAvailability(baseCount: 0, paCount: numbers[0], raCount: numbers[1])
        case 3...: return StatRuneAvailability(baseCount: numbers[0], paCount: numbers[1], raCount: numbers[2])
        default: return nil
        }
    }

    // MARK: - Format simple (fallback)

    private func parseSimpleFormat(line: String) -> Stat? {
        let tokens = tokenize(line)
        guard !tokens.isEmpty else { return nil }

        let numbers = extractNumbers(line)
        guard let value = numbers.first else { return nil }
        let range = extractParenRange(line)
        guard let name = extractAnyName(tokens: tokens) else { return nil }

        // Présence de "%" → distingue résistance % vs fixe
        let hasPercent = line.contains("%")
        let nameForLookup = hasPercent ? "\(name) %" : name
        guard let kind = dictionary.lookupFuzzy(nameForLookup) ?? dictionary.lookupFuzzy(name) else {
            return nil
        }

        return Stat(
            kind: kind,
            value: value,
            minValue: range?.lowerBound,
            maxValue: range?.upperBound,
            availability: nil
        )
    }

    // MARK: - Helpers

    private func tokenize(_ line: String) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace || $0 == ":" }).map(String.init)
    }

    private func parseInt(_ token: String) -> Int? {
        // Un token "Int" pur ne contient que des chiffres (avec éventuellement
        // +, -, ou un suffixe "%" qu'on ignore).
        guard !token.isEmpty else { return nil }
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "+%"))
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "-" }) else { return nil }
        return Int(trimmed)
    }

    private func isWordToken(_ token: String) -> Bool {
        // Un mot a au moins 2 lettres consécutives et pas de chiffre
        let letters = token.filter { $0.isLetter }
        return letters.count >= 2 && !token.contains(where: { $0.isNumber })
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

    private func extractLeadingName(tokens: [String]) -> String? {
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

    /// Récupère le nom à partir de TOUS les tokens qui ressemblent à un mot
    /// (utilisé en fallback quand le format est "28 Intelligence" ou "1 Portée 88").
    /// Filtre les tokens trop courts (1-2 lettres) qui ne sont vraisemblablement
    /// pas le nom de la stat (parasite OCR comme "do").
    private func extractAnyName(tokens: [String]) -> String? {
        let words = tokens.filter { tok in
            guard isWordToken(tok) else { return false }
            // Garde les mots de 3+ lettres OU les mots courts connus (PA, PM, RA, PO)
            if tok.count >= 3 { return true }
            let lower = tok.lowercased()
            return ["pa", "pm", "ra", "po"].contains(lower)
        }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
