import Foundation

/// Table canonique des poids de runes pour Dofus 3.
///
/// Sources :
/// - darckoune/fm_assistant `init/effect_weights.json` (52 effets, poids unitaire par 1 point de stat)
/// - Dafous 2026 (mise à jour Unity, confirme la plupart des valeurs)
/// - EasyFM `Configuration.csv` (densités runes base/Pa/Ra)
///
/// Concepts clés :
/// - **Poids unitaire** : ce que coûte 1 point de stat dans le puits (ex: 1 point de PA = 100 poids)
/// - **Bonus en points** : combien de points de stat une rune apporte (ex: Pa Vi → +15 vita)
/// - **Poids total d'une rune** : `bonus_points × unit_weight`
///
/// Règle d'or Dofus : `reliquat ≥ poids_rune` → SUCCÈS GARANTI (pose safe).
public enum RuneWeights {

    /// Poids unitaire (puits par 1 point de stat) par `characteristicId` DofusDB.
    /// Fallback à 1.0 si une stat n'est pas listée.
    public static let unitWeights: [Int: Double] = [
        // Stats spéciales (lourdes)
        1: 100.0,    // PA
        23: 90.0,    // PM
        19: 51.0,    // Portée
        // Invocations : id à confirmer via DofusDB sync, poids = 30
        // Dommages
        16: 20.0,    // Dommages
        // Soin / CC / Sagesse
        18: 10.0,    // % Critique
        49: 10.0,    // Soins
        12: 3.0,     // Sagesse
        48: 3.0,     // Prospection
        25: 2.0,     // Puissance
        // Esquive/Tacle
        78: 4.0,     // Fuite
        79: 4.0,     // Tacle
        // Stats primaires (poids 1)
        10: 1.0,     // Force
        13: 1.0,     // Chance
        14: 1.0,     // Agilité
        15: 1.0,     // Intelligence
        // Stats à poids unitaire faible
        11: 0.25,    // Vitalité (Dafous 2026 ; darckoune disait 0.2 — Dofus 3 a recalibré)
        44: 0.1,     // Initiative
        40: 2.5,     // Pods
        // Résistances en pourcentage
        33: 6.0, 34: 6.0, 35: 6.0, 36: 6.0, 37: 6.0,
        // Résistances fixes
        54: 2.0, 55: 2.0, 56: 2.0, 57: 2.0, 58: 2.0,
        // Dommages élémentaires
        88: 5.0, 89: 5.0, 90: 5.0, 91: 5.0, 92: 5.0,
    ]

    /// Stats qui n'ont qu'une rune Base en jeu (pas de Pa ni Ra disponibles).
    /// Validé en live Dofus 3 (2026).
    public static let baseOnlyStats: Set<Int> = [
        1,    // PA
        23,   // PM
        19,   // Portée
        16,   // Dommages (global)
        18,   // % Critique
        49,   // Soins
        // Résistances en % (id 33-37) → base seulement en Dofus 3
        33, 34, 35, 36, 37,
    ]

    /// Stats avec rune Base + Pa + Ra (rangs complets).
    /// Inclut explicitement les résistances fixes (Dofus 3 a Pa/Ra pour celles-ci).
    /// On ne les liste pas en dur ici — c'est le défaut quand pas dans baseOnly ni baseAndPaOnly.

    /// Stats avec rune Base + Pa seulement (pas de Ra).
    /// Validé en live Dofus 3 (2026).
    public static let baseAndPaOnlyStats: Set<Int> = [
        // Dommages élémentaires
        88, 89, 90, 91, 92,
        48,   // Prospection
        78,   // Fuite
        79,   // Tacle
    ]

    /// Cap d'over par stat : on ne peut pas dépasser `max_naturel + (101 / unitWeight)`.
    /// Concrètement : 101 poids d'over max par stat (ex: 404 vita à 0.25, 1010 ini à 0.1, 1 PA/PM).
    public static let maxOverWeightPerStat: Double = 101.0

    /// Bonus de stat apporté par une rune selon (stat, rang).
    ///
    /// Retourne `nil` si la rune n'existe pas en jeu pour cette combinaison
    /// (ex: pas de Pa PA, pas de Ra Ré%Feu, pas de Ra Dommage Feu, etc.).
    public static func bonusPoints(for stat: StatKind, power: Rune.Power) -> Int? {
        let id = stat.characteristicId
        // Filtres d'existence des runes
        if baseOnlyStats.contains(id) && power != .base { return nil }
        if baseAndPaOnlyStats.contains(id) && power == .ra { return nil }

        switch id {
        case 11:  // Vitalité — runes Vi/PaVi/RaVi
            switch power {
            case .base: return 5
            case .pa: return 15
            case .ra: return 50
            }
        case 44:  // Initiative — uniquement Ra Ini en jeu (densité 100)
            // En réalité darckoune ne liste que value=10 pour Ini, mais en Dofus 3
            // moderne il y a Ini/PaIni/RaIni. On garde 10/30/100.
            switch power {
            case .base: return 10
            case .pa: return 30
            case .ra: return 100
            }
        case 40:  // Pods
            switch power {
            case .base: return 4
            case .pa: return 10
            case .ra: return 20
            }
        default:
            // Stats standards : densité 1/3/10
            switch power {
            case .base: return 1
            case .pa: return 3
            case .ra: return 10
            }
        }
    }

    /// Poids unitaire d'une stat. Fallback à 1.0 si stat inconnue.
    public static func unitWeight(of stat: StatKind) -> Double {
        unitWeights[stat.characteristicId] ?? 1.0
    }

    /// Poids total d'une rune dans le puits = `bonus_points × unit_weight`.
    /// Retourne nil si la rune n'existe pas pour cette stat.
    public static func weight(of rune: Rune) -> Double? {
        guard let bonus = bonusPoints(for: rune.kind, power: rune.power) else { return nil }
        return Double(bonus) * unitWeight(of: rune.kind)
    }

    /// Cap d'over en points de stat pour une stat donnée (101 / poids_unitaire).
    /// Ex: Vita (0.25) → 404 points d'over, PA (100) → 1.01 → 1 point d'over max.
    public static func maxOverPoints(for stat: StatKind) -> Int {
        let unit = unitWeight(of: stat)
        guard unit > 0 else { return 0 }
        return Int(maxOverWeightPerStat / unit)
    }

    /// Liste exhaustive des runes existantes pour une stat donnée.
    /// Utile pour itérer sur les rangs disponibles dans les stratégies.
    public static func availableRunes(for stat: StatKind) -> [Rune] {
        let id = stat.characteristicId
        if baseOnlyStats.contains(id) {
            return [Rune(kind: stat, power: .base)]
        }
        if baseAndPaOnlyStats.contains(id) {
            return [Rune(kind: stat, power: .base), Rune(kind: stat, power: .pa)]
        }
        return [
            Rune(kind: stat, power: .base),
            Rune(kind: stat, power: .pa),
            Rune(kind: stat, power: .ra),
        ]
    }
}
