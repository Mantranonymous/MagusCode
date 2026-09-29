using System.Globalization;
using MagusBot.Core.Models;

namespace MagusBot.Core.Strategies;

/// <summary>
/// Stratégie d'exo en pourcentage (Do Sort, Do Distance, Do Mêlée, Do Arme).
///
/// <b>Source</b> : <c>bot_fm_exo_do_percent_logique.md</c> (20 mai 2026).
///
/// ## Mécanique
///
/// - <b>Poids rune</b> : 15 par 1%
/// - <b>Cap exo total</b> : 101 de poids
/// - <b>Over max théorique</b> : 6% (15×6=90 &lt; 101)
/// - <b>Taux SC pur</b> : ~1% par tentative
/// - <b>2ᵉ % ne passe QU'EN SC</b> : SN consomme le puits sans poser le %
///
/// ## Machine à états en 3 phases
///
/// 1. <b>Phase 1 (drop puits)</b> : provoquer chute d'une stat lourde pour avoir
///    reliquat ≥ 30 (1%) ou ≥ 60 (2%). Magus ne provoque PAS le drop lui-même
///    au MVP — l'utilisateur reçoit une instruction explicite.
/// 2. <b>Phase 2 (max lignes)</b> : tant que reliquat ≥ 15 et lignes non max, on
///    pose des runes pour remplir le tampon anti-EC.
/// 3. <b>Phase 3 (spam exo)</b> : tant que reliquat ≥ 15, on spam la rune exo
///    via inventaire calibré. SC → posé.
///
/// ## Règles absolues hard-codées
///
/// 1. Stop si exo target déjà posé (target+ atteinte)
/// 2. Pour exo 2% : nécessite que 1% soit déjà sur l'item
/// 3. Stop si exo 1% saute pendant tentative 2%
/// 4. Cap PWRG total ≤ 101 (refuser sinon)
/// </summary>
public sealed class ExoPercentStrategy : IDecisionStrategy
{
    public sealed record Variant(int CharacteristicId, int TargetPercent, string DisplayName)
    {
        public static Variant DoSort(int percent) => new(123, percent, $"+{percent}% Do Sort");
        public static Variant DoDistance(int percent) => new(120, percent, $"+{percent}% Do Distance");
    }

    public Variant Var { get; }
    public string Name => $"Exo {Var.DisplayName}";

    /// <summary>Poids d'une rune Do Per % (poids fixe = 15 par 1%, source Millenium).</summary>
    private const double RuneWeightConst = 15.0;
    /// <summary>Cap dur PWRG total Ankama.</summary>
    private const double PwrgCap = 101.0;

    private readonly MagingStrategy _maging = new();

    public ExoPercentStrategy(Variant variant) => Var = variant;

    public Decision Decide(GameStateSnapshot snapshot, PresetBundle preset, ItemSpec? spec)
    {
        if (snapshot.Item is not { } item || item.Stats.Count == 0)
            return new Decision.Blocked(new BlockReason.NoItem());
        if (spec is null)
            return new Decision.Blocked(new BlockReason.NoItemSpec());

        var exoKind = new StatKind(Var.CharacteristicId);
        var currentExo = item.StatMatching(exoKind)?.Value ?? 0;
        var goal = Var.TargetPercent;

        // === Règle absolue 1 : exo atteint → finished ===
        if (currentExo >= goal)
            return new Decision.Finished($"{Var.DisplayName} à {currentExo} → exo réussi ! ⚠ Ne plus poser de runes.");

        // === Règle absolue 2 : pour le 2%, le 1% doit déjà être posé ===
        if (goal == 2 && currentExo < 1)
        {
            return new Decision.Blocked(new BlockReason.NoActionPossible(
                $"Tentative d'exo +2% {Var.DisplayName} impossible : " +
                $"le +1% doit déjà être posé sur l'item (actuel: {currentExo}%). " +
                $"Lance d'abord le scénario +1% {Var.DisplayName.Replace($"+{goal}% ", "")}"));
        }

        // === Règle absolue 4 : cap PWRG total ===
        var pwrgCurrent = TotalWeight(item);
        if (pwrgCurrent + RuneWeightConst > PwrgCap)
        {
            return new Decision.Blocked(new BlockReason.NoActionPossible(
                $"PWRG total ({FormatNumber(pwrgCurrent)}) + rune ({FormatNumber(RuneWeightConst)}) " +
                $"> cap {FormatNumber(PwrgCap)}. " +
                "Provoque la chute d'une stat lourde (PA poids 100, PM 90, PO 51) " +
                "via spam de runes sur stats voisines au max pour libérer de la place."));
        }

        var reliquat = snapshot.Reliquat?.Density ?? 0;
        var reliquatMinForAttempt = 15.0; // 15 = poids 1 rune
        var reliquatMinPhase1 = goal == 1 ? 30.0 : 60.0;

        // === Phase 1 : Préparation du puits ===
        if (reliquat < reliquatMinForAttempt)
        {
            return new Decision.Blocked(new BlockReason.NoActionPossible(
                $"Reliquat insuffisant ({FormatNumber(reliquat)}/{FormatNumber(reliquatMinPhase1)}). " +
                $"**Phase 1 — Drop puits** : provoque la chute d'une stat lourde." + Environment.NewLine +
                $"• Idéal pour {goal}% {Var.DisplayName} : puits ~{FormatNumber(reliquatMinPhase1)}+" + Environment.NewLine +
                "• Méthode : pose des runes lourdes sur tes stats AU MAX (Sa, CC, Do)" + Environment.NewLine +
                "• Quand une stat lourde chute (PA→100, PM→90, PO→51), puits se remplit" + Environment.NewLine +
                $"• Une fois reliquat ≥ {FormatNumber(reliquatMinForAttempt)}, relance la session"));
        }

        // === Phase 2 : Maximisation des lignes (tampon anti-EC) ===
        var lissage = NeedsLissage(item, snapshot, preset, spec, exoKind);
        if (lissage is not null) return lissage;

        // === Phase 3 : Spam de l'exo ===
        var exoRune = new Rune(exoKind, RunePower.Pa);  // rune Pa Do Sort/Dist (poids 15)
        var snConsumesReliquatNote = goal == 1
            ? "SC ou SN posent le 1% (SN consomme du puits)"
            : "⚠ Seul SC pose le 2%, SN consomme inutilement le puits";

        var cyclesEstimes = (int)(reliquat / RuneWeightConst);
        var explanation = $"{Var.DisplayName} — Phase 3 (spam). " +
                          $"Reliquat {FormatNumber(reliquat)}, PWRG {FormatNumber(pwrgCurrent)}/{FormatNumber(PwrgCap)}. " +
                          $"Tentatives possibles ce cycle: {cyclesEstimes}. {snConsumesReliquatNote}.";

        return new Decision.ApplyRune(exoRune, exoKind, explanation);
    }

    /// <summary>
    /// Vérifie si on doit lisser les stats secondaires avant de tenter l'exo.
    /// Critère : il existe au moins une stat sous son target avec value ≥ 0.
    /// </summary>
    private Decision? NeedsLissage(Item item, GameStateSnapshot snapshot, PresetBundle preset, ItemSpec spec, StatKind exoKind)
    {
        var unfinished = item.Stats.Any(stat =>
        {
            if (stat.Kind == exoKind) return false;
            if (stat.Value < 0) return false;
            if (!preset.Stats.Targets.TryGetValue(stat.Kind, out var t) || !t.Enabled) return false;
            return stat.Value < t.Target;
        });
        if (!unfinished) return null;
        return _maging.Decide(snapshot, preset, spec);
    }

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
