using MagusBot.Core.Models;

namespace MagusBot.Core.Strategies;

/// <summary>
/// Stratégie Leveling : maximise l'XP gagnée par click sans se soucier du jet.
/// Préfère les runes les plus denses (Ra > Pa > base) sur les stats où elles
/// passent encore (i.e., distance suffisante pour le rang).
/// </summary>
public sealed class LevelingStrategy : IDecisionStrategy
{
    public string Name => "Leveling XP";

    private sealed record Candidate(
        Stat Stat,
        StatTarget Target,
        int Distance,
        RunePower BestRank,
        int DensityScore);

    public Decision Decide(GameStateSnapshot snapshot, PresetBundle preset, ItemSpec? spec)
    {
        if (snapshot.Item is not { } item || item.Stats.Count == 0)
            return new Decision.Blocked(new BlockReason.NoItem());

        var candidates = new List<Candidate>();
        foreach (var stat in item.Stats)
        {
            if (!preset.Stats.Targets.TryGetValue(stat.Kind, out var target) || !target.Enabled) continue;
            if (stat.Value >= target.Target) continue;
            if (stat.MaxValue is { } max && stat.Value > max) continue;

            var distance = target.Target - stat.Value;
            var rule = preset.Config.Rule(stat.Kind);
            var rank = PickHighestRank(distance, rule);
            candidates.Add(new Candidate(stat, target, distance, rank, rank.Density()));
        }

        if (candidates.Count == 0)
            return new Decision.Finished("Item full ! Pose un autre item ou un nouveau jet pour continuer le leveling.");

        // Tri : densité DESC (gros gain XP) puis distance DESC
        candidates.Sort((a, b) =>
        {
            if (a.DensityScore != b.DensityScore) return b.DensityScore.CompareTo(a.DensityScore);
            return b.Distance.CompareTo(a.Distance);
        });

        var chosen = candidates[0];
        var rune = new Rune(chosen.Stat.Kind, chosen.BestRank);
        var statName = spec?.Spec(chosen.Stat.Kind)?.DisplayName ?? $"stat #{chosen.Stat.Kind.CharacteristicId}";

        var explanation = $"Leveling : rune {rune.Power.ShortLabel().ToUpperInvariant()} sur {statName} (densité {rune.Power.Density()})." +
                          Environment.NewLine +
                          $"Distance {chosen.Distance} → gain XP estimé proportionnel à la densité. " +
                          "Si reliquat bas → risque normal, on fait pas de jet ici.";
        return new Decision.ApplyRune(rune, chosen.Stat.Kind, explanation);
    }

    private static RunePower PickHighestRank(int distance, ConfigRule rule)
    {
        // En leveling, on veut la plus grosse rune POSSIBLE (= la plus dense)
        if (rule.UseRa && distance >= 10) return RunePower.Ra;    // Ra +10 passe si distance ≥ 10
        if (rule.UsePa && distance >= 3) return RunePower.Pa;     // Pa +3 passe si distance ≥ 3
        return RunePower.Base;
    }
}
