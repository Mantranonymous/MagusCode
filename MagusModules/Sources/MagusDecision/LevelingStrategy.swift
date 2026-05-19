import Foundation
import MagusCore

/// Stratégie Leveling : maximise l'XP gagnée par click sans se soucier du jet.
/// Préfère les runes les plus denses (Ra > Pa > base) sur les stats où elles
/// passent encore (i.e., distance suffisante pour le rang).
public struct LevelingStrategy: DecisionStrategy {

    public let name = "Leveling XP"

    public init() {}

    public func decide(
        snapshot: GameStateSnapshot,
        preset: PresetBundle,
        spec: ItemSpec?
    ) -> Decision {
        guard let item = snapshot.item, !item.stats.isEmpty else {
            return .blocked(reason: .noItem)
        }

        // En leveling on cherche la stat où on peut poser la plus GROSSE rune
        struct Candidate {
            let stat: Stat
            let target: StatTarget
            let distance: Int
            let bestRank: Rune.Power
            let densityScore: Int  // densité de la rune choisie
        }

        var candidates: [Candidate] = []
        for stat in item.stats {
            guard let target = preset.stats.targets[stat.kind], target.enabled else { continue }
            if stat.value >= target.target { continue }
            if let max = stat.maxValue, stat.value > max { continue }

            let distance = target.target - stat.value
            let rule = preset.config.rule(for: stat.kind)
            let rank = pickHighestRank(distance: distance, rule: rule)
            candidates.append(Candidate(
                stat: stat,
                target: target,
                distance: distance,
                bestRank: rank,
                densityScore: rank.density
            ))
        }

        if candidates.isEmpty {
            return .finished(explanation: "Item full ! Pose un autre item ou un nouveau jet pour continuer le leveling.")
        }

        // Tri : densité DESC (gros gain XP) puis distance DESC
        candidates.sort { a, b in
            if a.densityScore != b.densityScore { return a.densityScore > b.densityScore }
            return a.distance > b.distance
        }

        let chosen = candidates[0]
        let rune = Rune(kind: chosen.stat.kind, power: chosen.bestRank)
        let statName = spec?.spec(matching: chosen.stat.kind)?.displayName ?? "stat #\(chosen.stat.kind.characteristicId)"

        let explanation = """
        Leveling : rune \(rune.power.rawValue.uppercased()) sur \(statName) (densité \(rune.power.density)).
        Distance \(chosen.distance) → gain XP estimé proportionnel à la densité. \
        Si reliquat bas → risque normal, on fait pas de jet ici.
        """
        return .applyRune(rune, on: chosen.stat.kind, explanation: explanation)
    }

    private func pickHighestRank(distance: Int, rule: ConfigRule) -> Rune.Power {
        // En leveling, on veut la plus grosse rune POSSIBLE (= la plus dense)
        if rule.useRA && distance >= 10 { return .ra }    // Ra +10 passe si distance ≥ 10
        if rule.usePA && distance >= 3 { return .pa }     // Pa +3 passe si distance ≥ 3
        return .base
    }
}
