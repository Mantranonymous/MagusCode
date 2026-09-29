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
            // **Pas de fallback à 0** : si on n'arrive pas à lire la valeur, on saute
            // la stat plutôt que de la fabriquer. Sinon une stat à -4 (Tacle, etc.)
            // dont la valeur OCR foire serait vue comme 0 → le moteur tenterait de la mager.
            guard let value = findNearbyValue(
                aroundRange: nameRange,
                tokens: tokens,
                expectedMin: statSpec.minValue,
                expectedMax: statSpec.maxValue
            ) else { continue }

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
        // DofusDB encode certaines stats en magnitude positive même si l'item les
        // applique en négatif (Tacle, Fuite, Esquive PA/PM, parfois Prospection).
        // On accepte donc les valeurs lues côté OCR dans `[expectedMin, expectedMax]`
        // ET dans `[-expectedMax, -expectedMin]` (le miroir).
        let mirrorMin = -expectedMax
        let mirrorMax = -expectedMin
        func matchesSpecOrMirror(_ a: Int, _ b: Int) -> Bool {
            (a == expectedMin && b == expectedMax) || (a == mirrorMin && b == mirrorMax)
        }

        // 1. Pattern Dofus 3 strict : `[Min] [Max] [Value] [Name]`
        //    Ex : "21 30 30 Agilité" → Value = 30 (3ème).
        //    Ex négatif : "-4 -6 -6 Tacle" — match miroir car spec dit 4-6.
        let nameStart = range.lowerBound
        if nameStart >= 3,
           let n1 = parseSignedInt(tokens[nameStart - 3]),
           let n2 = parseSignedInt(tokens[nameStart - 2]),
           let n3 = parseSignedInt(tokens[nameStart - 1]),
           matchesSpecOrMirror(n1, n2) {
            return n3
        }

        // 2. Pattern simple : `[Value] [Name]` immédiatement adjacent.
        //    On **exclut explicitement les boundaries** (expectedMin/max et leurs miroirs)
        //    — sinon dans le format Dofus 3 "Min Max Name" (icône cache la value),
        //    on prendrait Max comme value, ce qui donnerait par ex. Résistance Air 10
        //    au lieu de 0.
        if nameStart >= 1,
           let v = parseSignedInt(tokens[nameStart - 1]),
           v != expectedMin, v != expectedMax,
           v != mirrorMin, v != mirrorMax {
            let plausiblePos = (expectedMin - 5)...(expectedMax + abs(expectedMax) + 50)
            let plausibleNeg = (mirrorMin - 50 - abs(mirrorMin))...(mirrorMax + 5)
            if plausiblePos.contains(v) || plausibleNeg.contains(v) {
                return v
            }
        }

        // 3. Fallback radius — chercher dans un voisinage.
        // **Préfère les nombres AVANT le nom** : en Dofus 3, la value est dans la
        // colonne Effets (juste avant le nom). Les nombres APRÈS sont Modif/Pa/Ra
        // (donc -3 en colonne Modif peut être proche mais n'est PAS la value).
        // On ne regarde APRÈS que si rien n'a été trouvé avant.
        let radius = 6
        let lo = max(0, range.lowerBound - radius)
        let hi = min(tokens.count - 1, range.upperBound + radius)
        guard lo <= hi else { return nil }

        let extendedMax = max(expectedMax, expectedMax + abs(expectedMax) + 50)
        let extendedMin: Int = expectedMin < 0 ? expectedMin - 20 : 0
        let acceptedPos = extendedMin...extendedMax
        let acceptedNeg = (mirrorMin - 50 - abs(mirrorMin))...max(mirrorMax, 0)

        // Filtre commun : accepte v si dans la fenêtre attendue (positive ou miroir)
        // et n'est pas un boundary trivial (min/max attendu).
        func isCandidate(_ v: Int) -> Bool {
            if v == expectedMin || v == expectedMax { return false }
            if v == mirrorMin || v == mirrorMax { return false }
            return acceptedPos.contains(v) || acceptedNeg.contains(v)
        }

        // Phase A : balayage AVANT le nom uniquement (colonne Effets en Dofus 3)
        var beforeCandidates: [(distance: Int, value: Int)] = []
        for i in lo..<range.lowerBound {
            guard let v = parseSignedInt(tokens[i]) else { continue }
            guard isCandidate(v) else { continue }
            beforeCandidates.append((range.lowerBound - i, v))
        }
        if let best = beforeCandidates.sorted(by: { $0.distance < $1.distance }).first {
            return best.value
        }

        // Phase B : fallback APRÈS le nom (Modif/Pa/Ra) — seulement si rien avant.
        // C'est moins fiable mais permet de quand même remonter quelque chose.
        var afterCandidates: [(distance: Int, value: Int)] = []
        for i in (range.upperBound + 1)...hi where i < tokens.count {
            guard let v = parseSignedInt(tokens[i]) else { continue }
            guard isCandidate(v) else { continue }
            afterCandidates.append((i - range.upperBound, v))
        }
        return afterCandidates.sorted(by: { $0.distance < $1.distance }).first?.value
    }

    private func parseSignedInt(_ token: String) -> Int? {
        let trimmed = token
            .trimmingCharacters(in: CharacterSet(charactersIn: "+%"))
            .replacingOccurrences(of: "\u{2212}", with: "-")  // U+2212 → ASCII
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "-" }) else { return nil }
        return Int(trimmed)
    }
}
