using System.Globalization;
using MagusBot.Core.Models;

namespace MagusBot.Core.Strategies;

/// <summary>
/// Stratégie "Maging classique" V3 — puits-aware, table de poids canonique.
///
/// Améliorations vs V2 :
/// - Utilise <see cref="RuneWeights"/> (table canonique 52 effets) au lieu de densité 1/3/10 abstraite
/// - Choisit la rune via <b>bonus</b> (5/15/50 pour Vita, 1/3/10 pour Force, etc.)
/// - Cap over 101 poids par stat respecté (404 vita, 1 PA/PM)
/// - Préfère runes <b>safe</b> (reliquat ≥ poids_rune → SC garanti)
/// - <b>Lisse</b> les grosses stats d'abord (PA, PM, CC, Do, Soin)
/// </summary>
public sealed class MagingStrategy : IDecisionStrategy
{
    public string Name => "Maging classique";

    private readonly ReliquatTracker _reliquatTracker = new();

    private sealed record Candidate(
        Stat Stat,
        StatTarget Target,
        int Distance,
        int Priority,
        int RunesNeeded,
        bool IsHighValue);

    public Decision Decide(GameStateSnapshot snapshot, PresetBundle preset, ItemSpec? spec)
    {
        if (snapshot.Item is not { } item || item.Stats.Count == 0)
            return new Decision.Blocked(new BlockReason.NoItem());

        if (preset.Stats.Targets.Count == 0)
            return new Decision.Blocked(new BlockReason.NoPresetSelected());

        var currentReliquat = snapshot.Reliquat?.Density ?? 0;
        var candidates = new List<Candidate>();

        foreach (var stat in item.Stats)
        {
            if (!preset.Stats.Targets.TryGetValue(stat.Kind, out var target) || !target.Enabled)
                continue;
            // Stats négatives : on ne mage pas (convention). C'est un malus assumé.
            // Si l'user veut vraiment y toucher, il active la target manuellement.
            if (stat.Value < 0) continue;
            if (stat.Value >= target.Target) continue;

            // **Cap absolu = target du preset**. On ne fait JAMAIS d'over involontaire.
            // Si l'user veut over, il met target > maxValue dans son preset (slider).
            // Le cap d'over système (101/poids_unitaire) n'est utilisé que comme garde-fou
            // si target > maxValue + over_cap (improbable).
            var maxOverAbsolute = (stat.MaxValue ?? target.Target) + RuneWeights.MaxOverPoints(stat.Kind);
            var absoluteMax = Math.Min(target.Target, maxOverAbsolute);
            if (stat.Value >= absoluteMax) continue;

            var distance = target.Target - stat.Value;
            var needed = RunesNeededToReach(distance, stat.Kind);
            var isHighValue = RuneWeights.UnitWeight(stat.Kind) >= 10.0;

            candidates.Add(new Candidate(stat, target, distance, target.Priority, needed, isHighValue));
        }

        if (candidates.Count == 0)
        {
            return new Decision.Finished("Toutes les stats sont à leur cible. Tu peux poser une rune de transcendance si l'item n'est pas en exo/over.");
        }

        // Tri : grosses stats (high-value) d'abord, puis priorité, puis nb runes restantes.
        // Inspiré d'ExoFast : à priorité égale, on prend la stat qui demande le plus de runes
        // (= plus gros chantier restant). Force 17→20 (3 runes) bat Vita 90→100 (2 runes).
        candidates.Sort((a, b) =>
        {
            if (a.IsHighValue != b.IsHighValue) return a.IsHighValue ? -1 : 1;
            if (a.Priority != b.Priority) return b.Priority.CompareTo(a.Priority);
            return b.RunesNeeded.CompareTo(a.RunesNeeded);
        });

        // **CHANGEMENT MAJEUR vs avant (P29)** : on itère TOUS les candidats jusqu'à
        // trouver une rune viable. Avant, on essayait uniquement le 1er candidat
        // (le mieux prioritaire) et on bloquait s'il n'avait pas de rune.
        // Conséquence : si Vitalité 99/100 (Base Vi overshoot) bloquait, on ne
        // tentait jamais Agilité 24/30 qui pourtant avait Pa Ag disponible.
        (Rune Rune, int Bonus, double Weight)? pick = null;
        Candidate? chosen = null;
        string? firstFailureMsg = null;

        foreach (var candidate in candidates)
        {
            var rule = preset.Config.Rule(candidate.Stat.Kind);
            var found = PickBestRune(
                candidate.Stat,
                candidate.Target.Target,
                candidate.Distance,
                currentReliquat,
                rule,
                preset.DepletedRunes);
            if (found is not null)
            {
                pick = found;
                chosen = candidate;
                break;
            }
            // Mémorise le motif d'échec du 1er candidat (le mieux prioritaire)
            // pour le diagnostic si TOUS les candidats échouent.
            if (firstFailureMsg is null)
            {
                var wouldFindWithoutDepletion = PickBestRune(
                    candidate.Stat,
                    candidate.Target.Target,
                    candidate.Distance,
                    currentReliquat,
                    rule,
                    new HashSet<Rune>()) is not null;
                var name = DisplayName(candidate.Stat.Kind, spec);
                firstFailureMsg = wouldFindWithoutDepletion
                    ? $"Toutes les runes pour {name} sont marquées épuisées (val {candidate.Stat.Value}/{candidate.Target.Target}). Vérifie l'inventaire et reset si nécessaire."
                    : $"Pas de rune qui tient sans dépasser la cible sur {name} (val {candidate.Stat.Value}/{candidate.Target.Target}).";
            }
        }

        if (pick is null || chosen is null)
        {
            var count = candidates.Count;
            var baseMsg = firstFailureMsg ?? "Aucune action possible.";
            var suffix = count > 1 ? $" ({count} stats testées sans succès)" : "";
            return new Decision.Blocked(new BlockReason.NoActionPossible(baseMsg + suffix));
        }

        var statName = DisplayName(chosen.Stat.Kind, spec);
        var safety = _reliquatTracker.Evaluate(pick.Value.Rune, currentReliquat);
        string safetyText = safety switch
        {
            ReliquatTracker.SafetyLevel.Safe s => $"✓ Safe (puits absorbe, marge {FormatNumber(s.MarginAfter)})",
            ReliquatTracker.SafetyLevel.Risky r => $"⚠ Risqué (puits manque {FormatNumber(r.ReliquatShortBy)} de poids)",
            ReliquatTracker.SafetyLevel.VeryRisky => "⚠⚠ Puits vide — pose à l'aveugle",
            ReliquatTracker.SafetyLevel.Impossible => "Impossible",
            _ => ""
        };

        var rangeInfo = (chosen.Stat.MinValue, chosen.Stat.MaxValue) is ({ } mn, { } mx)
            ? $"(range {mn}-{mx})"
            : "";

        var explanation = $"{statName} à {chosen.Stat.Value}/{chosen.Target.Target} {rangeInfo} — distance {chosen.Distance}." +
                          Environment.NewLine +
                          $"→ Rune {pick.Value.Rune.Power.ShortLabel().ToUpperInvariant()} +{pick.Value.Bonus} " +
                          $"(poids {FormatNumber(pick.Value.Weight)}). {safetyText}";

        return new Decision.ApplyRune(pick.Value.Rune, chosen.Stat.Kind, explanation.Trim());
    }

    // MARK: - Choix de la rune

    /// <summary>
    /// Sélectionne la meilleure rune pour atteindre la stat sans déborder.
    /// Stratégie :
    /// 1. Filtrer : pas de rune qui ferait dépasser le cap over absolu
    /// 2. Préférer la plus grosse rune dont le bonus ≤ distance × 1.2 (légère tolérance over)
    /// 3. Parmi celles-là, préférer une rune SAFE (reliquat ≥ poids_rune)
    /// 4. Respecter le <c>ConfigRule</c> (useBase/usePA/useRA si l'utilisateur a désactivé un rang)
    /// 5. Fallback : la plus petite rune dispo
    /// </summary>
    private (Rune Rune, int Bonus, double Weight)? PickBestRune(
        Stat stat,
        int target,
        int distance,
        double currentReliquat,
        ConfigRule rule,
        IReadOnlySet<Rune> depletedRunes)
    {
        // **Cap absolu = target**. Aucune rune ne doit pousser au-delà.
        var absoluteMax = target;
        var allRunes = RuneWeights.AvailableRunes(stat.Kind);

        var viable = new List<(Rune Rune, int Bonus, double Weight)>();
        foreach (var rune in allRunes)
        {
            if (depletedRunes.Contains(rune)) continue;
            switch (rune.Power)
            {
                case RunePower.Base:
                    if (!rule.UseBase) continue;
                    break;
                case RunePower.Pa:
                    if (!rule.UsePa) continue;
                    if (!rule.EffectivePaThreshold.Allows(stat.Value)) continue;
                    break;
                case RunePower.Ra:
                    if (!rule.UseRa) continue;
                    if (!rule.EffectiveRaThreshold.Allows(stat.Value)) continue;
                    break;
            }
            var bonus = RuneWeights.BonusPoints(stat.Kind, rune.Power);
            var weight = RuneWeights.Weight(rune);
            if (bonus is null || weight is null) continue;
            if (stat.Value + bonus.Value > absoluteMax) continue;
            viable.Add((rune, bonus.Value, weight.Value));
        }

        if (viable.Count == 0) return null;

        // Trier du plus gros bonus au plus petit
        viable.Sort((a, b) => b.Bonus.CompareTo(a.Bonus));

        // 1) La plus grosse rune SAFE qui matche la distance (bonus ≤ distance × 1.2)
        foreach (var entry in viable)
        {
            if (entry.Bonus <= distance * 1.2 && currentReliquat >= entry.Weight)
                return entry;
        }
        // 2) La plus grosse rune qui matche la distance (sans safety)
        foreach (var entry in viable)
        {
            if (entry.Bonus <= distance * 1.2)
                return entry;
        }
        // 3) Toutes les runes overshoot → la plus petite
        return viable[^1];
    }

    private static string DisplayName(StatKind kind, ItemSpec? spec) =>
        spec?.Spec(kind)?.DisplayName ?? $"stat #{kind.CharacteristicId}";

    /// <summary>
    /// Nombre de runes pour parcourir <c>distance</c> points, en utilisant la plus grosse
    /// rune disponible pour cette stat. ExoFast utilise ce critère pour le tie-breaking
    /// à priorité égale (cf. doc "Les priorités").
    /// </summary>
    private static int RunesNeededToReach(int distance, StatKind kind)
    {
        var bonuses = new List<int>();
        foreach (RunePower power in Enum.GetValues<RunePower>())
        {
            var b = RuneWeights.BonusPoints(kind, power);
            if (b is not null) bonuses.Add(b.Value);
        }
        var maxBonus = bonuses.Count == 0 ? 1 : bonuses.Max();
        return (distance + maxBonus - 1) / maxBonus; // ceil
    }

    private static string FormatNumber(double d) =>
        d % 1 == 0
            ? d.ToString("F0", CultureInfo.InvariantCulture)
            : d.ToString("F1", CultureInfo.InvariantCulture);
}
