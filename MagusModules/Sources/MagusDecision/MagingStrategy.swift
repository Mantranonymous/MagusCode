import Foundation
import MagusCore

/// Stratégie "Maging classique" V3 — puits-aware, table de poids canonique.
///
/// Améliorations vs V2 :
/// - Utilise `RuneWeights` (table canonique 52 effets) au lieu de densité 1/3/10 abstraite
/// - Choisit la rune via **bonus** (5/15/50 pour Vita, 1/3/10 pour Force, etc.)
/// - Cap over 101 poids par stat respecté (404 vita, 1 PA/PM)
/// - Préfère runes **safe** (reliquat ≥ poids_rune → SC garanti)
/// - **Lisse** les grosses stats d'abord (PA, PM, CC, Do, Soin)
public struct MagingStrategy: DecisionStrategy {

    public let name = "Maging classique"

    private let reliquatTracker = ReliquatTracker()

    public init() {}

    public func decide(
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec?
    ) -> Decision {
        guard let item = snapshot.item, !item.stats.isEmpty else {
            return .blocked(reason: .noItem)
        }
        guard !preset.stats.targets.isEmpty else {
            return .blocked(reason: .noPresetSelected)
        }

        struct Candidate {
            let stat: Stat
            let target: StatTarget
            let distance: Int
            let priority: Int
            let runesNeeded: Int   // nb de runes pour atteindre la cible (tie-breaking)
            let isHighValue: Bool  // PA/PM/CC/Do/Soin → lisser d'abord
        }

        let currentReliquat = snapshot.reliquat?.density ?? 0
        var candidates: [Candidate] = []

        for stat in item.stats {
            guard let target = preset.stats.targets[stat.kind], target.enabled else { continue }
            // Stats négatives : on ne mage pas (convention). C'est un malus assumé.
            // Si l'user veut vraiment y toucher, il active la target manuellement.
            if stat.value < 0 { continue }
            if stat.value >= target.target { continue }

            // **Cap absolu = target du preset**. On ne fait JAMAIS d'over involontaire.
            // Si l'user veut over, il met target > maxValue dans son preset (slider).
            // Le cap d'over système (101/poids_unitaire) n'est utilisé que comme garde-fou
            // si target > maxValue + over_cap (improbable).
            let maxOverAbsolute = (stat.maxValue ?? target.target) + RuneWeights.maxOverPoints(for: stat.kind)
            let absoluteMax = min(target.target, maxOverAbsolute)
            if stat.value >= absoluteMax { continue }

            let distance = target.target - stat.value
            let needed = runesNeededToReach(distance: distance, kind: stat.kind)
            let isHighValue = RuneWeights.unitWeight(of: stat.kind) >= 10.0

            candidates.append(Candidate(
                stat: stat, target: target, distance: distance,
                priority: target.priority, runesNeeded: needed,
                isHighValue: isHighValue
            ))
        }

        guard !candidates.isEmpty else {
            return .finished(explanation: "Toutes les stats sont à leur cible. Tu peux poser une rune de transcendance si l'item n'est pas en exo/over.")
        }

        // Tri : grosses stats (high-value) d'abord, puis priorité, puis nb runes restantes.
        // Inspiré d'ExoFast : à priorité égale, on prend la stat qui demande le plus de runes
        // (= plus gros chantier restant). Force 17→20 (3 runes) bat Vita 90→100 (2 runes).
        candidates.sort { a, b in
            if a.isHighValue != b.isHighValue { return a.isHighValue }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.runesNeeded > b.runesNeeded
        }

        // **CHANGEMENT MAJEUR vs avant** : on itère TOUS les candidats jusqu'à
        // trouver une rune viable. Avant, on essayait uniquement le 1er candidat
        // (le mieux prioritaire) et on bloquait s'il n'avait pas de rune.
        // Conséquence : si Vitalité 99/100 (Base Vi overshoot) bloquait, on ne
        // tentait jamais Agilité 24/30 qui pourtant avait Pa Ag disponible.
        var pickResult: (rune: Rune, bonus: Int, weight: Double)?
        var chosen: Candidate?
        var firstFailureMsg: String?
        for candidate in candidates {
            let rule = preset.config.rule(for: candidate.stat.kind)
            if let p = pickBestRune(
                stat: candidate.stat,
                target: candidate.target.target,
                distance: candidate.distance,
                currentReliquat: currentReliquat,
                rule: rule,
                depletedRunes: preset.depletedRunes
            ) {
                pickResult = p
                chosen = candidate
                break
            }
            // Mémorise le motif d'échec du 1er candidat (le mieux prioritaire)
            // pour le diagnostic si TOUS les candidats échouent.
            if firstFailureMsg == nil {
                let wouldFindWithoutDepletion = pickBestRune(
                    stat: candidate.stat,
                    target: candidate.target.target,
                    distance: candidate.distance,
                    currentReliquat: currentReliquat,
                    rule: rule,
                    depletedRunes: []
                ) != nil
                let name = displayName(for: candidate.stat.kind, spec: spec)
                firstFailureMsg = wouldFindWithoutDepletion
                    ? "Toutes les runes pour \(name) sont marquées épuisées (val \(candidate.stat.value)/\(candidate.target.target)). Vérifie l'inventaire et reset si nécessaire."
                    : "Pas de rune qui tient sans dépasser la cible sur \(name) (val \(candidate.stat.value)/\(candidate.target.target))."
            }
        }
        guard let pick = pickResult, let chosen = chosen else {
            // Aucun candidat n'a de rune viable : on remonte le motif du mieux prioritaire,
            // augmenté du nombre de candidats testés pour aider au diagnostic.
            let count = candidates.count
            let baseMsg = firstFailureMsg ?? "Aucune action possible."
            let suffix = count > 1 ? " (\(count) stats testées sans succès)" : ""
            return .blocked(reason: .noActionPossible(baseMsg + suffix))
        }

        let statName = displayName(for: chosen.stat.kind, spec: spec)
        let safety = reliquatTracker.evaluate(rune: pick.rune, currentReliquat: currentReliquat)
        let safetyText: String = {
            switch safety {
            case .safe(let m):
                return "✓ Safe (puits absorbe, marge \(formatNumber(m)))"
            case .risky(let s):
                return "⚠ Risqué (puits manque \(formatNumber(s)) de poids)"
            case .veryRisky:
                return "⚠⚠ Puits vide — pose à l'aveugle"
            case .impossible:
                return "Impossible"
            }
        }()
        let rangeInfo: String = {
            guard let mn = chosen.stat.minValue, let mx = chosen.stat.maxValue else { return "" }
            return "(range \(mn)-\(mx))"
        }()

        let explanation = """
        \(statName) à \(chosen.stat.value)/\(chosen.target.target) \(rangeInfo) — distance \(chosen.distance).
        → Rune \(pick.rune.power.rawValue.uppercased()) +\(pick.bonus) (poids \(formatNumber(pick.weight))). \(safetyText)
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        return .applyRune(pick.rune, on: chosen.stat.kind, explanation: explanation)
    }

    // MARK: - Choix de la rune

    /// Sélectionne la meilleure rune pour atteindre la stat sans déborder.
    /// Stratégie :
    /// 1. Filtrer : pas de rune qui ferait dépasser le cap over absolu
    /// 2. Préférer la plus grosse rune dont le bonus ≤ distance × 1.2 (légère tolérance over)
    /// 3. Parmi celles-là, préférer une rune SAFE (reliquat ≥ poids_rune)
    /// 4. Respecter le `ConfigRule` (useBase/usePA/useRA si l'utilisateur a désactivé un rang)
    /// 5. Fallback : la plus petite rune dispo
    private func pickBestRune(
        stat: Stat,
        target: Int,
        distance: Int,
        currentReliquat: Double,
        rule: ConfigRule,
        depletedRunes: Set<Rune>
    ) -> (rune: Rune, bonus: Int, weight: Double)? {
        // **Cap absolu = target**. Aucune rune ne doit pousser au-delà.
        let absoluteMax = target
        let allRunes = RuneWeights.availableRunes(for: stat.kind)

        // Construit la liste enrichie + filtre les rangs désactivés par config + over-cap
        // + les runes détectées comme épuisées en inventaire pendant la session
        // + les seuils Pa/Ra basés sur la valeur courante (style ExoFast).
        let viable = allRunes.compactMap { rune -> (rune: Rune, bonus: Int, weight: Double)? in
            if depletedRunes.contains(rune) { return nil }
            switch rune.power {
            case .base:
                if !rule.useBase { return nil }
            case .pa:
                if !rule.usePA { return nil }
                if !rule.paValueThreshold.allows(currentValue: stat.value) { return nil }
            case .ra:
                if !rule.useRA { return nil }
                if !rule.raValueThreshold.allows(currentValue: stat.value) { return nil }
            }
            guard let bonus = RuneWeights.bonusPoints(for: stat.kind, power: rune.power),
                  let weight = RuneWeights.weight(of: rune) else { return nil }
            if stat.value + bonus > absoluteMax { return nil }
            return (rune, bonus, weight)
        }

        guard !viable.isEmpty else { return nil }

        // Trier du plus gros bonus au plus petit
        let sorted = viable.sorted { $0.bonus > $1.bonus }

        // 1) La plus grosse rune SAFE qui matche la distance (bonus ≤ distance × 1.2)
        for entry in sorted {
            if Double(entry.bonus) <= Double(distance) * 1.2 && currentReliquat >= entry.weight {
                return entry
            }
        }
        // 2) La plus grosse rune qui matche la distance (sans safety)
        for entry in sorted {
            if Double(entry.bonus) <= Double(distance) * 1.2 {
                return entry
            }
        }
        // 3) Toutes les runes overshoot → la plus petite
        return sorted.last
    }

    private func displayName(for kind: StatKind, spec: ItemSpec?) -> String {
        spec?.spec(matching: kind)?.displayName ?? "stat #\(kind.characteristicId)"
    }

    /// Nombre de runes pour parcourir `distance` points, en utilisant la plus grosse
    /// rune disponible pour cette stat. ExoFast utilise ce critère pour le tie-breaking
    /// à priorité égale (cf. doc "Les priorités").
    /// Ex: Vita distance 50 avec Ra Vi (+50) → 1 rune ; Force distance 5 avec Ra Fo (+10) → 1 rune.
    private func runesNeededToReach(distance: Int, kind: StatKind) -> Int {
        let bonuses = Rune.Power.allCases.compactMap {
            RuneWeights.bonusPoints(for: kind, power: $0)
        }
        let maxBonus = bonuses.max() ?? 1
        return (distance + maxBonus - 1) / maxBonus  // ceil
    }

    private func formatNumber(_ d: Double) -> String {
        if d.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", d)
        }
        return String(format: "%.1f", d)
    }
}
