import Foundation
import MagusCore

/// Service de raisonnement autour du reliquat (puits) Dofus.
///
/// Formule canonique (source : darckoune/fm_assistant `item.py:107-123`) :
/// ```
/// real_earned   = Σ(line.lastModification × line.effectWeight)
/// theorical     = +rune.weight si SC, 0 si SN/EN, -rune.weight si EC
/// Δreliquat     = -(real_earned - theorical)
/// reliquat     += Δreliquat
/// ```
///
/// **Règle d'or** : si `reliquat ≥ poids_rune`, le puits absorbe TOUT le poids
/// nécessaire en cas de perte → la pose est SAFE (succès garanti, ou SN sans
/// perte visible sur les jets). Voir EasyFM `Perte()` :385-424.
///
/// **Règle bonus** : si la perte calculée dépasse strictement le poids demandé,
/// le surplus alimente le puits (le puits PEUT GROSSIR).
public struct ReliquatTracker: Sendable {

    /// Niveau de risque d'une pose de rune.
    public enum SafetyLevel: Sendable, Equatable {
        /// Reliquat ≥ poids_rune → succès quasi-garanti, puits absorbe toute perte.
        case safe(marginAfter: Double)
        /// Reliquat < poids_rune mais > 0 → SN possible, perte partielle.
        case risky(reliquatShortBy: Double)
        /// Reliquat à 0 → pose à l'aveugle, toute la perte tombe sur les jets.
        case veryRisky
        /// La rune n'existe pas pour cette stat (ex: Pa PA).
        case impossible

        public var label: String {
            switch self {
            case .safe: return "Safe"
            case .risky: return "Risqué"
            case .veryRisky: return "Très risqué"
            case .impossible: return "Impossible"
            }
        }
    }

    public init() {}

    /// Évalue le niveau de risque de poser une rune avec le reliquat courant.
    public func evaluate(rune: Rune, currentReliquat: Double) -> SafetyLevel {
        guard let weight = RuneWeights.weight(of: rune) else {
            return .impossible
        }
        if currentReliquat >= weight {
            return .safe(marginAfter: currentReliquat - weight)
        }
        if currentReliquat > 0 {
            return .risky(reliquatShortBy: weight - currentReliquat)
        }
        return .veryRisky
    }

    /// Prédiction du reliquat après une pose donnée (hypothèse outcome).
    /// - SC : `reliquat - poids_rune` (peut tomber à 0, jamais négatif)
    /// - SN : `reliquat` inchangé (la perte est absorbée + puits regrossit du surplus)
    /// - EC : `reliquat + poids_rune` (la rune retombe → poids regagné)
    public func predictReliquatAfter(
        rune: Rune,
        currentReliquat: Double,
        outcome: HistoryOutcome
    ) -> Double {
        guard let weight = RuneWeights.weight(of: rune) else { return currentReliquat }
        switch outcome {
        case .criticalSuccess:
            return max(0, currentReliquat - weight)
        case .neutralSuccess:
            return currentReliquat
        case .criticalFail:
            return currentReliquat + weight
        }
    }

    /// Calcule le poids "réel" gagné sur l'item entre deux snapshots.
    /// Somme des `Δstat × poids_unitaire(stat)` pour toutes les stats qui ont changé.
    /// Positif si l'item s'est amélioré globalement, négatif si dégradation.
    public func realWeightChange(diff: StateDiff) -> Double {
        var total: Double = 0
        for change in diff.changes {
            if case let .statChanged(kind, oldValue, newValue) = change {
                let unit = RuneWeights.unitWeight(of: kind)
                let delta = newValue - oldValue
                total += Double(delta) * unit
            }
        }
        return total
    }

    /// Trie des runes candidates par sécurité décroissante puis poids décroissant.
    /// Permet à MagingStrategy de préférer les runes safe avant les risquées.
    public func sortedBySafety(
        _ runes: [Rune],
        currentReliquat: Double
    ) -> [(rune: Rune, safety: SafetyLevel, weight: Double)] {
        let scored = runes.compactMap { rune -> (Rune, SafetyLevel, Double)? in
            guard let w = RuneWeights.weight(of: rune) else { return nil }
            return (rune, evaluate(rune: rune, currentReliquat: currentReliquat), w)
        }
        return scored.sorted { a, b in
            // Safe d'abord, puis plus gros poids d'abord (= plus efficace par click)
            let aSafe = a.1.isSafe ? 1 : 0
            let bSafe = b.1.isSafe ? 1 : 0
            if aSafe != bSafe { return aSafe > bSafe }
            return a.2 > b.2
        }
    }
}

/// Résultat d'un combine de FM. Reflète l'histoire FM côté Dofus.
public enum HistoryOutcome: Sendable, Equatable {
    case criticalSuccess  // SC : la rune passe sans perte
    case neutralSuccess   // SN : la rune passe mais une autre stat baisse (puits utilisé)
    case criticalFail     // EC : la rune ne passe pas (souvent une stat baisse aussi)
}

extension ReliquatTracker.SafetyLevel {
    public var isSafe: Bool {
        if case .safe = self { return true }
        return false
    }
}
