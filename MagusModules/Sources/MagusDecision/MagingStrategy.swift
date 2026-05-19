import Foundation
import MagusCore

/// Stratégie "Maging classique" basée sur TargetResolve, version v2 plus prudente :
/// - Skip stats déjà OVER (au-dessus du max théorique) pour ne pas tout perdre
/// - Skip stats DÉJÀ AU MAX (rien à gagner)
/// - Si reliquat = 0 ET ratio item-rempli haut → préfère rune base (moins de risque)
/// - Tri : priorité × (distance restante / range total) → cible les plus déficitaires
public struct MagingStrategy: DecisionStrategy {

    public let name = "Maging classique"

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
            let distance: Int        // target - value (toujours > 0 ici)
            let priority: Int
            let urgency: Double      // distance / rangeSpan
        }

        var candidates: [Candidate] = []
        for stat in item.stats {
            guard let target = preset.stats.targets[stat.kind], target.enabled else { continue }

            // Skip si déjà au max ou plus
            if stat.value >= target.target { continue }

            // Skip si en over par rapport au max théorique (très dangereux de toucher)
            if let max = stat.maxValue, stat.value > max { continue }

            let distance = target.target - stat.value
            let span: Double = {
                if let min = stat.minValue, let max = stat.maxValue, max > min {
                    return Double(max - min)
                }
                return Double(max(1, distance))
            }()
            let urgency = Double(distance) / span
            candidates.append(Candidate(
                stat: stat,
                target: target,
                distance: distance,
                priority: target.priority,
                urgency: urgency
            ))
        }

        if candidates.isEmpty {
            return .finished(explanation: "Toutes les stats sont à leur cible. Tu peux poser une rune de transcendance si l'item n'est pas en exo/over.")
        }

        // Tri : priorité DESC, puis urgency DESC
        candidates.sort { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return a.urgency > b.urgency
        }

        let chosen = candidates[0]
        let rule = preset.config.rule(for: chosen.stat.kind)

        // Sélection du rang : règle ×20 + safety reliquat
        let reliquatLow = (snapshot.reliquat?.density ?? 0) <= 1
        let runeRank = selectRuneRank(
            distance: chosen.distance,
            rule: rule,
            reliquatLow: reliquatLow
        )
        let rune = Rune(kind: chosen.stat.kind, power: runeRank)

        let statName = displayName(for: chosen.stat.kind, spec: spec)
        let rangeInfo: String
        if let min = chosen.stat.minValue, let max = chosen.stat.maxValue {
            rangeInfo = "(range \(min)-\(max))"
        } else {
            rangeInfo = ""
        }
        let reliquatText: String
        if let r = snapshot.reliquat {
            reliquatText = r.hasCapacity
                ? "Reliquat \(r.formatted) → puits exploitable."
                : "Pas de reliquat — risque \(reliquatLow ? "élevé" : "modéré"), préfère rune plus petite."
        } else {
            reliquatText = "Reliquat inconnu."
        }

        let explanation = """
        \(statName) à \(chosen.stat.value)/\(chosen.target.target) \(rangeInfo) — distance \(chosen.distance).
        → Rune \(rune.power.rawValue.uppercased()) (densité \(rune.power.density)). \(reliquatText)
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        return .applyRune(rune, on: chosen.stat.kind, explanation: explanation)
    }

    // MARK: - Helpers

    private func selectRuneRank(distance: Int, rule: ConfigRule, reliquatLow: Bool) -> Rune.Power {
        // Si reliquat bas, on penche vers une rune plus petite (sécurité)
        if reliquatLow {
            if rule.usePA && distance >= rule.thresholdPA * 2 { return .pa }
            if rule.useBase { return .base }
        }
        if rule.useRA && distance >= rule.thresholdRA { return .ra }
        if rule.usePA && distance >= rule.thresholdPA { return .pa }
        if rule.useBase { return .base }
        return .pa
    }

    private func displayName(for kind: StatKind, spec: ItemSpec?) -> String {
        spec?.spec(matching: kind)?.displayName ?? "stat #\(kind.characteristicId)"
    }
}
