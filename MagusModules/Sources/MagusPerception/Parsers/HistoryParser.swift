import Foundation
import MagusCore

/// Parse l'historique des combines. Lignes typiques (Dofus 3) :
///   "+ 1 Vitalité"     → gain explicite
///   "-1 Sagesse"       → perte
///   "1 Soin"           → entrée sans signe (généralement positive)
///   "Échec"            → combine raté
///   "+ reliquat"       → reliquat gagné
///   "- reliquat"       → reliquat perdu
///
/// L'OCR peut parfois perdre le signe `-` (très fin). Sans signe explicite,
/// on retourne `.unknown` plutôt que de défauter à positif (pour éviter de
/// faussement annoncer un gain).
public struct HistoryParser: Sendable {

    /// Caractères considérés comme signe négatif (incluant Unicode minus, en-dash, em-dash).
    private static let negativeSigns: Set<Character> = ["-", "−", "–", "—", "‒"]

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

        // Détection explicite d'EC (échec critique)
        if lower.contains("échec") || lower.contains("echec") || lower.contains("raté") {
            return MageHistoryEntry(result: .criticalFail, kind: .unknown, raw: clean)
        }

        // Entrée "reliquat" sans valeur numérique
        if lower.contains("reliquat") {
            let hasNegativeSign = Self.containsNegativeSign(clean)
            let hasPositiveSign = clean.contains("+")
            let result: MageHistoryEntry.Result
            if hasNegativeSign { result = .criticalFail }
            else if hasPositiveSign { result = .criticalSuccess }
            else { result = .neutralSuccess }
            return MageHistoryEntry(result: result, kind: .unknown, delta: 0, raw: clean)
        }

        // Détection du signe
        let sign = detectSign(in: clean)

        let numbers = extractNumbers(clean)
        guard let firstNumber = numbers.first else {
            return nil
        }

        // Delta avec le signe détecté
        let delta: Int
        switch sign {
        case .negative: delta = -abs(firstNumber)
        case .positive: delta = abs(firstNumber)
        case .none: delta = firstNumber   // sans signe, valeur brute (souvent positive)
        }

        let statName = extractStatName(line: clean)
        let kind = statName.flatMap { dictionary.lookupFuzzy($0) }

        let result: MageHistoryEntry.Result
        switch sign {
        case .negative: result = .criticalFail
        case .positive: result = .criticalSuccess
        case .none:
            // Sans signe explicite : impossible de garantir SC vs SN.
            // On marque .unknown pour ne pas faussement annoncer un gain.
            result = .unknown
        }

        return MageHistoryEntry(
            result: result,
            kind: .unknown,
            targetStat: kind,
            delta: delta,
            raw: clean
        )
    }

    // MARK: - Sign detection

    private enum Sign {
        case negative, positive, none
    }

    private func detectSign(in line: String) -> Sign {
        // Le signe est typiquement en tête, possiblement avec un espace
        let firstNonSpace = line.first(where: { !$0.isWhitespace })
        if let c = firstNonSpace {
            if Self.negativeSigns.contains(c) { return .negative }
            if c == "+" { return .positive }
        }
        // Fallback : "gain"/"perd" dans le texte
        let lower = line.lowercased()
        if lower.contains("gain") { return .positive }
        if lower.contains("perd") || lower.contains("perte") { return .negative }
        return .none
    }

    private static func containsNegativeSign(_ s: String) -> Bool {
        s.contains(where: { negativeSigns.contains($0) })
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
            // Pas un nombre pur, pas une ponctuation pure
            guard !tok.allSatisfy(\.isNumber),
                  !tok.allSatisfy({ "()+-/−–—‒".contains($0) }) else { return false }
            // Au moins 3 lettres, OU un mot court connu (PA, PM, RA, PO, PV)
            let letters = tok.filter(\.isLetter)
            if letters.count >= 3 { return true }
            let lower = tok.lowercased()
            return ["pa", "pm", "ra", "po", "pv"].contains(lower)
        }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
