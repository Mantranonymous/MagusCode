import Foundation
import MagusCore

/// Prédit quelle(s) stat(s) tomberont si la pose suivante est un EC (échec critique)
/// ou SN (succès neutre — puits épuisé).
///
/// Porté depuis EasyFM `ChercherLeJetQuiBaisse()` (lignes 576-596).
///
/// Logique :
/// 1. Si un exo est présent et qu'on ne pose pas la même rune → l'exo tombe en priorité
/// 2. Si une stat est en OVERMAX → elle tombe en priorité
/// 3. Sinon : tirage probabiliste pondéré par le poids unitaire de la stat
///    (les stats à fort poids unitaire sont plus "épargnées" car elles coûtent
///    cher à remplacer dans le puits)
public struct RiskSimulator: Sendable {

    public struct PredictedDrop: Sendable, Equatable {
        public let kind: StatKind
        public let probability: Double      // 0-1
        public let estimatedPointsLost: Int
        public let weightFreed: Double      // poids qui retombera dans le puits si chute
    }

    public init() {}

    /// Prédit les chutes les plus probables si la rune `rune` est posée et finit en EC/SN.
    /// Retourne le top N stats (3 par défaut), triées par probabilité décroissante.
    public func predictFallsIfBadOutcome(
        item: Item,
        runePosed: Rune,
        weightToLose: Double,
        topN: Int = 3
    ) -> [PredictedDrop] {
        var candidates: [(stat: Stat, score: Double)] = []

        // 1. Exos (stats non natives, identifiées par minValue == nil)
        let exoStats = item.stats.filter { $0.minValue == nil && $0.value > 0 }
        for exo in exoStats where exo.kind != runePosed.kind {
            // Exo tombe quasi systématiquement si pas la cible courante
            candidates.append((exo, score: 100))
        }

        // 2. Stats en OVERMAX (value > max naturel)
        for stat in item.stats {
            guard let max = stat.maxValue else { continue }
            if stat.value > max && stat.kind != runePosed.kind {
                candidates.append((stat, score: 80))
            }
        }

        // 3. Autres stats avec value > 0 (sauf la cible et celles à 0)
        for stat in item.stats {
            if stat.kind == runePosed.kind { continue }
            if stat.value <= 0 { continue }
            if exoStats.contains(where: { $0.kind == stat.kind }) { continue }

            let unitWeight = RuneWeights.unitWeight(of: stat.kind)
            // Score d'épargne EasyFM : si pwr_unitaire > weightToLose, chance épargné = ratio.
            // Une stat à fort poids unitaire = moins probable de tomber (épargnée).
            let escapeProbability = unitWeight > weightToLose ? (weightToLose / unitWeight) : 1.0
            // Score brut = probabilité de tomber (inverse de l'épargne, modulée par 10).
            let score = 10.0 * escapeProbability
            candidates.append((stat, score: score))
        }

        guard !candidates.isEmpty else { return [] }

        // Normalisation en probabilités
        let totalScore = candidates.map(\.score).reduce(0, +)
        guard totalScore > 0 else { return [] }

        let drops = candidates.map { c -> PredictedDrop in
            let prob = c.score / totalScore
            let unitWeight = RuneWeights.unitWeight(of: c.stat.kind)
            // Estimation des points perdus : on tente d'absorber `weightToLose` sur cette stat
            let pointsLost = max(1, Int((weightToLose / max(unitWeight, 0.01)).rounded()))
            let clamped = min(pointsLost, c.stat.value)
            return PredictedDrop(
                kind: c.stat.kind,
                probability: prob,
                estimatedPointsLost: clamped,
                weightFreed: Double(clamped) * unitWeight
            )
        }

        return Array(drops.sorted { $0.probability > $1.probability }.prefix(topN))
    }

    /// Texte synthétique pour l'overlay : "Si EC : Vita -8 (45%), Force -3 (30%)..."
    public func summary(for drops: [PredictedDrop], dictionary: ((StatKind) -> String)? = nil) -> String {
        guard !drops.isEmpty else { return "" }
        let parts = drops.map { d -> String in
            let name = dictionary?(d.kind) ?? "#\(d.kind.characteristicId)"
            let pct = Int((d.probability * 100).rounded())
            return "\(name) −\(d.estimatedPointsLost) (\(pct)%)"
        }
        return parts.joined(separator: ", ")
    }
}
