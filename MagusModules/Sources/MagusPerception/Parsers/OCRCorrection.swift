import Foundation

/// Corrections de caractères ambigus fréquents en OCR.
/// On les applique de façon ciblée : sur les chiffres (l→1, O→0) et sur les mots (1→l).
public enum OCRCorrection {

    /// Confusions courantes vues sur Vision OCR avec polices Dofus.
    public static let digitSubstitutions: [Character: Character] = [
        "l": "1", "I": "1", "|": "1",
        "O": "0", "o": "0", "Q": "0", "D": "0",
        "S": "5", "s": "5",
        "B": "8",
        "Z": "2", "z": "2",
        "G": "6",
        "T": "7",
        "g": "9", "q": "9",
    ]

    public static let letterSubstitutions: [Character: Character] = [
        "1": "l", "0": "O", "5": "S", "8": "B",
    ]

    /// Tente de lire un Int à partir d'une string en appliquant des corrections
    /// successives si le premier essai échoue ou tombe hors range.
    /// Si la string contient des lettres, applique d'abord les substitutions
    /// (S→5, O→0, l→1, ...) puis parse le premier groupe de chiffres.
    public static func parseInt(_ text: String, expectedRange: ClosedRange<Int>? = nil) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLetters = trimmed.contains(where: { $0.isLetter })

        // Si lettres présentes, essai prioritaire avec substitutions
        if hasLetters {
            let corrected = applyDigitSubstitutions(trimmed)
            if let v = firstInt(in: corrected),
               expectedRange.map({ $0.contains(v) }) ?? true {
                return v
            }
        }

        // Parse direct (pour strings déjà "propres")
        let cleaned = stripNonDigits(trimmed)
        if let v = Int(cleaned), expectedRange.map({ $0.contains(v) }) ?? true {
            return v
        }

        // Fallback : substitution puis premier int
        let corrected = applyDigitSubstitutions(trimmed)
        if let v = firstInt(in: corrected),
           expectedRange.map({ $0.contains(v) }) ?? true {
            return v
        }
        return nil
    }

    /// Remplace les caractères confondus par des chiffres dans une string où on attend un nombre.
    public static func applyDigitSubstitutions(_ text: String) -> String {
        String(text.map { digitSubstitutions[$0] ?? $0 })
    }

    /// Garde uniquement chiffres et signes. U+2212 (MINUS SIGN) → ASCII "-".
    public static func stripNonDigits(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .filter { $0.isNumber || $0 == "-" || $0 == "+" }
    }

    /// Sépare d'une string un nombre potentiel (premier groupe consécutif de chiffres).
    public static func firstInt(in text: String) -> Int? {
        var current = ""
        var foundDigit = false
        for c in text {
            if c.isNumber {
                current.append(c)
                foundDigit = true
            } else if foundDigit {
                break
            }
        }
        return Int(current)
    }

    /// Récupère le dernier groupe consécutif de chiffres dans une string.
    /// Utile pour les zones type "Sink 87%" où le nombre est en fin.
    public static func lastInt(in text: String) -> Int? {
        var groups: [String] = []
        var current = ""
        for c in text {
            if c.isNumber {
                current.append(c)
            } else if !current.isEmpty {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups.last.flatMap { Int($0) }
    }
}
