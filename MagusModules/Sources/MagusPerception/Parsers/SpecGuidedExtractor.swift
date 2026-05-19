import Foundation
import MagusCore

/// Extraction "spec-guidée" : pour chaque stat attendue d'un ItemSpec qui n'a pas
/// été parsée par le parser ligne-à-ligne, cherche le nom dans le texte OCR brut
/// et extrait la valeur adjacente. Permet de récupérer les stats que Vision OCR
/// fragmente entre colonnes (ex: "° Tacle" sur une ligne, "0" sur une autre).
public struct SpecGuidedExtractor: Sendable {

    private let dictionary: StatDictionary

    public init(dictionary: StatDictionary) {
        self.dictionary = dictionary
    }

    /// Enrichit la liste de stats parsées avec celles manquantes du spec
    /// que l'on peut retrouver dans le texte OCR.
    public func enrich(parsed: [Stat], with spec: ItemSpec, ocrText: String) -> [Stat] {
        let parsedKinds = Set(parsed.map(\.kind))
        var result = parsed
        let tokens = tokenize(ocrText)

        for statSpec in spec.stats {
            guard !parsedKinds.contains(statSpec.kind) else { continue }
            guard let nameRange = findNameRange(for: statSpec, in: tokens) else {
                continue
            }
            let value = findNearbyValue(
                aroundRange: nameRange,
                tokens: tokens,
                expectedMin: statSpec.minValue,
                expectedMax: statSpec.maxValue
            ) ?? 0  // si on a trouvé le nom mais pas de nombre proche, on suppose 0

            result.append(Stat(
                kind: statSpec.kind,
                value: value,
                minValue: statSpec.minValue,
                maxValue: statSpec.maxValue,
                availability: nil
            ))
        }
        return result
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\n" || $0 == ":" })
            .map(String.init)
    }

    // MARK: - Name matching

    private func findNameRange(for spec: StatSpec, in tokens: [String]) -> ClosedRange<Int>? {
        let targetKind = spec.kind
        let nameTokens = spec.displayName.split(separator: " ").map(String.init)
        let nameTokenCount = nameTokens.count

        for i in 0..<tokens.count {
            // Match multi-tokens : ex. "Dommage Terre"
            if nameTokenCount > 1, i + nameTokenCount <= tokens.count {
                let segment = Array(tokens[i..<(i + nameTokenCount)])
                let joined = segment.joined(separator: " ")
                if dictionary.lookup(joined) == targetKind
                    || dictionary.lookupFuzzy(joined) == targetKind {
                    return i...(i + nameTokenCount - 1)
                }
            }
            // Match single-token : "Tacle", "Fuite", "Vitalité"
            if let kind = dictionary.lookup(tokens[i]), kind == targetKind {
                return i...i
            }
        }
        return nil
    }

    // MARK: - Value extraction

    private func findNearbyValue(
        aroundRange range: ClosedRange<Int>,
        tokens: [String],
        expectedMin: Int,
        expectedMax: Int
    ) -> Int? {
        let radius = 4
        let lo = max(0, range.lowerBound - radius)
        let hi = min(tokens.count - 1, range.upperBound + radius)
        guard lo <= hi else { return nil }

        // Range tolérée : autorise un peu d'over par rapport au max théorique,
        // et autorise les valeurs proches de 0 (stat "0 X" très fréquent).
        let extendedMax = max(expectedMax, expectedMax + abs(expectedMax) + 50)
        let extendedMin: Int
        if expectedMin < 0 {
            extendedMin = expectedMin - 20
        } else {
            extendedMin = 0
        }
        let acceptedRange = extendedMin...extendedMax

        var inRangeCandidates: [(distance: Int, value: Int)] = []
        for i in lo...hi where !range.contains(i) {
            guard let v = parseSignedInt(tokens[i]) else { continue }
            // Évite de prendre min ou max théoriques comme value
            if v == expectedMin || v == expectedMax { continue }
            guard acceptedRange.contains(v) else { continue }
            let dist = abs(i - range.lowerBound)
            inRangeCandidates.append((dist, v))
        }

        // Si rien dans la range → on ne devine pas. Le caller default à 0
        // (cas typique : stat à 0 dont l'OCR n'a pas capté le chiffre).
        guard !inRangeCandidates.isEmpty else { return nil }
        return inRangeCandidates.sorted(by: { $0.distance < $1.distance }).first?.value
    }

    private func parseSignedInt(_ token: String) -> Int? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "+%"))
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "-" }) else { return nil }
        return Int(trimmed)
    }
}
