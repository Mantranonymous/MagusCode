using MagusBot.Core.Models;

namespace MagusBot.Core;

/// <summary>
/// Service de raisonnement autour du reliquat (puits) Dofus.
///
/// Formule canonique (source : darckoune/fm_assistant <c>item.py:107-123</c>) :
/// <code>
/// real_earned   = Σ(line.lastModification × line.effectWeight)
/// theorical     = +rune.weight si SC, 0 si SN/EN, -rune.weight si EC
/// Δreliquat     = -(real_earned - theorical)
/// reliquat     += Δreliquat
/// </code>
///
/// <b>Règle d'or</b> : si <c>reliquat ≥ poids_rune</c>, le puits absorbe TOUT le poids
/// nécessaire en cas de perte → la pose est SAFE (succès garanti, ou SN sans perte visible).
///
/// <b>Règle bonus</b> : si la perte calculée dépasse strictement le poids demandé,
/// le surplus alimente le puits (le puits PEUT GROSSIR).
/// </summary>
public sealed class ReliquatTracker
{
    /// <summary>Niveau de risque d'une pose de rune.</summary>
    public abstract record SafetyLevel
    {
        public abstract string Label { get; }
        public bool IsSafe => this is Safe;

        /// <summary>Reliquat ≥ poids_rune → succès quasi-garanti.</summary>
        public sealed record Safe(double MarginAfter) : SafetyLevel
        {
            public override string Label => "Safe";
        }
        /// <summary>Reliquat &lt; poids_rune mais &gt; 0 → SN possible, perte partielle.</summary>
        public sealed record Risky(double ReliquatShortBy) : SafetyLevel
        {
            public override string Label => "Risqué";
        }
        /// <summary>Reliquat à 0 → pose à l'aveugle, toute la perte tombe sur les jets.</summary>
        public sealed record VeryRisky : SafetyLevel
        {
            public override string Label => "Très risqué";
        }
        /// <summary>La rune n'existe pas pour cette stat (ex: Pa PA).</summary>
        public sealed record Impossible : SafetyLevel
        {
            public override string Label => "Impossible";
        }
    }

    /// <summary>Évalue le niveau de risque de poser une rune avec le reliquat courant.</summary>
    public SafetyLevel Evaluate(Rune rune, double currentReliquat)
    {
        var weight = RuneWeights.Weight(rune);
        if (weight is null) return new SafetyLevel.Impossible();
        if (currentReliquat >= weight) return new SafetyLevel.Safe(currentReliquat - weight.Value);
        if (currentReliquat > 0) return new SafetyLevel.Risky(weight.Value - currentReliquat);
        return new SafetyLevel.VeryRisky();
    }

    /// <summary>
    /// Prédiction du reliquat après une pose donnée (hypothèse outcome).
    /// SC : reliquat - poids_rune (clamp 0). SN : inchangé. EC : reliquat + poids_rune.
    /// </summary>
    public double PredictReliquatAfter(Rune rune, double currentReliquat, CombineResult outcome)
    {
        var weight = RuneWeights.Weight(rune);
        if (weight is null) return currentReliquat;
        return outcome switch
        {
            CombineResult.CriticalSuccess => Math.Max(0, currentReliquat - weight.Value),
            CombineResult.NeutralSuccess => currentReliquat,
            CombineResult.CriticalFail => currentReliquat + weight.Value,
            _ => currentReliquat
        };
    }

    /// <summary>
    /// Trie des runes candidates par sécurité décroissante puis poids décroissant.
    /// Permet à MagingStrategy de préférer les runes safe avant les risquées.
    /// </summary>
    public IReadOnlyList<(Rune Rune, SafetyLevel Safety, double Weight)> SortedBySafety(
        IEnumerable<Rune> runes,
        double currentReliquat)
    {
        var scored = new List<(Rune, SafetyLevel, double)>();
        foreach (var r in runes)
        {
            var w = RuneWeights.Weight(r);
            if (w is null) continue;
            scored.Add((r, Evaluate(r, currentReliquat), w.Value));
        }
        return scored
            .OrderByDescending(x => x.Item2.IsSafe)
            .ThenByDescending(x => x.Item3)
            .ToList();
    }
}
