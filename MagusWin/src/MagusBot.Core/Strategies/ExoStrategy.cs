using System.Globalization;
using MagusBot.Core.Models;

namespace MagusBot.Core.Strategies;

/// <summary>
/// Stratégie d'exo (PA / PM) V3 — méthode "lissage + tampon de stats sacrificielles".
///
/// <b>Principe correct</b> (validé par les pros FM Dofus) :
/// Pour un exo PA/PM sur item <b>sans PA/PM natif</b>, il ne faut PAS briser l'item à 0
/// puis tenter l'exo — sinon dès la première EC sur une rune de remontée, l'exo
/// dégage (il n'y a pas d'autre stat de poids ≥ pour absorber la chute).
///
/// La vraie méthode :
/// <list type="number">
/// <item><b>Lissage</b> : pousser TOUTES les stats au max (y compris les "sacrificielles"
///    comme prospection, résistances fixes, esquives, tacles, retraits)</item>
/// <item><b>Spam</b> : marteler Ga PA/PM via l'inventaire dans cet état "plein"</item>
/// <item><b>Absorption</b> : quand un EC tombe pendant le spam, les pertes sont absorbées
///    par les stats sacrificielles (au max → cible facile) avant de toucher l'exo</item>
/// <item><b>Recovery</b> : si une stat HIGH PRIORITY tombe (PA natif, CC, Do), MagingStrategy
///    la remet en priorité absolue avant de re-spam l'exo</item>
/// </list>
///
/// Machine à états :
/// - <c>alreadyDone</c> : <c>targetStat.value &gt; 0</c> → finished
/// - <c>nativeFell</c> : la stat exo est native mais à 0 → délègue MagingStrategy
/// - <c>needsLissage</c> : une stat est sous son max → délègue MagingStrategy
/// - <c>spamExo</c> : tout est lissé → spam Ga PA/PM
/// </summary>
public sealed class ExoStrategy : IDecisionStrategy
{
    public abstract record Variant
    {
        public abstract StatKind TargetKind { get; }
        public abstract int TargetValue { get; }
        public abstract string DisplayName { get; }

        public sealed record ExoPa : Variant
        {
            public override StatKind TargetKind => StatKind.PA;
            public override int TargetValue => 1;
            public override string DisplayName => "PA";
        }

        public sealed record ExoPm : Variant
        {
            public override StatKind TargetKind => StatKind.PM;
            public override int TargetValue => 1;
            public override string DisplayName => "PM";
        }

        /// <summary>
        /// Exo générique sur une stat non native (Do Sort, Do Distance, etc.).
        /// <c>Target</c> = pourcentage à atteindre (1 ou 2 typiquement).
        /// </summary>
        public sealed record Custom(int CharacteristicId, int Target, string Label) : Variant
        {
            public override StatKind TargetKind => new(CharacteristicId);
            public override int TargetValue => Target;
            public override string DisplayName => Label;
        }
    }

    public Variant Mode { get; }
    public string Name => $"Exo {Mode.DisplayName}";

    private readonly MagingStrategy _maging = new();
    private readonly SuccessProbabilityModel _probaModel = new();

    public ExoStrategy(Variant variant) => Mode = variant;

    public Decision Decide(GameStateSnapshot snapshot, PresetBundle preset, ItemSpec? spec)
    {
        if (snapshot.Item is not { } item || item.Stats.Count == 0)
            return new Decision.Blocked(new BlockReason.NoItem());
        if (spec is null)
            return new Decision.Blocked(new BlockReason.NoItemSpec());

        var targetKind = Mode.TargetKind;
        var currentValue = item.StatMatching(targetKind)?.Value ?? 0;
        var goal = Mode.TargetValue;

        // Cas 1 : exo atteint (>= cible) → finished
        if (currentValue >= goal)
            return new Decision.Finished($"{Mode.DisplayName} à {currentValue} → exo réussi !");

        // Cas 2 : la stat exo est NATIVE sur l'item mais elle est tombée à 0 → maging classique
        // pour la remettre. La rune normale fait le job (pas un vrai exo).
        if (spec.Spec(targetKind) is not null)
            return _maging.Decide(snapshot, preset, spec);

        // Cas 3 : on est en vrai exo. Vérifier si le lissage est complet.
        // **CHANGEMENT MAJEUR vs V2** : on n'inspecte plus le PWRG total (faux).
        // L'approche pro = item PLEIN au max sur toutes les lignes, sacrificielles incluses.
        var lissageDecision = NeedsLissage(item, snapshot, preset, spec);
        if (lissageDecision is not null) return lissageDecision;

        // Cas 4 : tout est lissé → on spam l'exo.
        var exoRune = new Rune(targetKind, RunePower.Base);
        var runeWeight = RuneWeights.Weight(exoRune);
        if (runeWeight is null)
            return new Decision.Blocked(new BlockReason.NoActionPossible($"Rune Ga {Mode.DisplayName} introuvable"));

        var pwrgCurrent = TotalWeight(item);

        var probas = _probaModel.Compute(new SuccessProbabilityModel.Inputs(
            Rune: exoRune,
            StatCurrentValue: 0,
            StatMin: 0,
            StatMax: 1,
            ItemLevel: spec.Level,
            PwrgCurrent: pwrgCurrent,
            PwrgMax: 100,
            PwrgCurrentStat: 0,
            IsExo: true,
            IsOver: false,
            PwrgOverEtExo: pwrgCurrent));

        var explanation = $"Exo {Mode.DisplayName} — spam Ga {Mode.DisplayName} dans l'inventaire. " +
                          $"Item lissé : PWRG {FormatNumber(pwrgCurrent)} (tampons sacrificiels actifs). " +
                          $"Poids rune: {FormatNumber(runeWeight.Value)}. {probas.Summary}. " +
                          "Budget moyen ~100 runes (taux SC ~1%).";

        return new Decision.ApplyRune(exoRune, targetKind, explanation);
    }

    /// <summary>
    /// Vérifie que toutes les stats utiles (y compris sacrificielles) sont au max.
    /// Une stat est considérée "à monter" si :
    /// - elle est dans le preset avec target &gt; value courante
    /// - ce n'est pas la stat exo elle-même
    /// - sa valeur courante n'est pas négative (les malus ne se remontent pas)
    /// </summary>
    private Decision? NeedsLissage(Item item, GameStateSnapshot snapshot, PresetBundle preset, ItemSpec spec)
    {
        var unfinished = item.Stats.Any(stat =>
        {
            if (stat.Kind == Mode.TargetKind) return false;
            if (stat.Value < 0) return false;
            if (!preset.Stats.Targets.TryGetValue(stat.Kind, out var t) || !t.Enabled) return false;
            return stat.Value < t.Target;
        });
        if (!unfinished) return null;
        return _maging.Decide(snapshot, preset, spec);
    }

    /// <summary>Poids total de l'item = Σ(stat.value × poids_unitaire) pour les stats positives.</summary>
    private static double TotalWeight(Item item)
    {
        double sum = 0;
        foreach (var stat in item.Stats)
        {
            if (stat.Value <= 0) continue;
            sum += stat.Value * RuneWeights.UnitWeight(stat.Kind);
        }
        return sum;
    }

    private static string FormatNumber(double d) =>
        d % 1 == 0
            ? d.ToString("F0", CultureInfo.InvariantCulture)
            : d.ToString("F1", CultureInfo.InvariantCulture);
}
