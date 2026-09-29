using MagusBot.Core.Models;

namespace MagusBot.Core;

/// <summary>
/// Table canonique des poids de runes pour Dofus 3.
///
/// Sources :
/// - darckoune/fm_assistant `init/effect_weights.json` (52 effets, poids unitaire par 1 point de stat)
/// - Dafous 2026 (mise à jour Unity, confirme la plupart des valeurs)
/// - EasyFM `Configuration.csv` (densités runes base/Pa/Ra)
///
/// Concepts clés :
/// - <b>Poids unitaire</b> : ce que coûte 1 point de stat dans le puits (ex: 1 point de PA = 100 poids)
/// - <b>Bonus en points</b> : combien de points de stat une rune apporte (ex: Pa Vi → +15 vita)
/// - <b>Poids total d'une rune</b> : <c>bonus_points × unit_weight</c>
///
/// Règle d'or Dofus : <c>reliquat ≥ poids_rune</c> → SUCCÈS GARANTI (pose safe).
///
/// IMPORTANT : la table doit rester strictement identique à la version Swift
/// (<c>MagusModules/Sources/MagusCore/Models/RuneWeights.swift</c>). Toute
/// divergence se traduit par un mauvais choix de runes par l'engine.
/// </summary>
public static class RuneWeights
{
    /// <summary>
    /// Poids unitaire (puits par 1 point de stat) par <c>characteristicId</c> DofusDB.
    /// Fallback à 1.0 si une stat n'est pas listée.
    /// </summary>
    public static readonly IReadOnlyDictionary<int, double> UnitWeightsById = new Dictionary<int, double>
    {
        // Stats spéciales (lourdes)
        { 1, 100.0 },   // PA
        { 23, 90.0 },   // PM
        { 19, 51.0 },   // Portée
        // Invocations : id à confirmer via DofusDB sync, poids = 30
        // Dommages
        { 16, 20.0 },   // Dommages
        // Soin / CC / Sagesse
        { 18, 10.0 },   // % Critique
        { 49, 10.0 },   // Soins
        { 12, 3.0 },    // Sagesse
        { 48, 3.0 },    // Prospection
        { 25, 2.0 },    // Puissance
        // Esquive/Tacle
        { 78, 4.0 },    // Fuite
        { 79, 4.0 },    // Tacle
        // Stats primaires (poids 1)
        { 10, 1.0 },    // Force
        { 13, 1.0 },    // Chance
        { 14, 1.0 },    // Agilité
        { 15, 1.0 },    // Intelligence
        // Stats à poids unitaire faible
        { 11, 0.25 },   // Vitalité (Dafous 2026 ; darckoune disait 0.2 — Dofus 3 a recalibré)
        { 44, 0.1 },    // Initiative
        { 40, 2.5 },    // Pods
        // Résistances en pourcentage
        { 33, 6.0 }, { 34, 6.0 }, { 35, 6.0 }, { 36, 6.0 }, { 37, 6.0 },
        // Résistances fixes
        { 54, 2.0 }, { 55, 2.0 }, { 56, 2.0 }, { 57, 2.0 }, { 58, 2.0 },
        // Dommages élémentaires
        { 88, 5.0 }, { 89, 5.0 }, { 90, 5.0 }, { 91, 5.0 }, { 92, 5.0 },
    };

    /// <summary>
    /// Stats qui n'ont qu'une rune Base en jeu (pas de Pa ni Ra disponibles).
    /// Validé en live Dofus 3 (2026).
    /// </summary>
    public static readonly IReadOnlySet<int> BaseOnlyStats = new HashSet<int>
    {
        1,   // PA
        23,  // PM
        19,  // Portée
        16,  // Dommages (global)
        18,  // % Critique
        49,  // Soins
        // Résistances en % (id 33-37) → base seulement en Dofus 3
        33, 34, 35, 36, 37,
    };

    /// <summary>
    /// Stats avec rune Base + Pa seulement (pas de Ra).
    /// Validé en live Dofus 3 (2026).
    /// </summary>
    public static readonly IReadOnlySet<int> BaseAndPaOnlyStats = new HashSet<int>
    {
        // Dommages élémentaires
        88, 89, 90, 91, 92,
        48, // Prospection
        78, // Fuite
        79, // Tacle
    };

    /// <summary>
    /// Cap d'over par stat : on ne peut pas dépasser <c>max_naturel + (101 / unitWeight)</c>.
    /// Concrètement : 101 poids d'over max par stat (ex: 404 vita à 0.25, 1010 ini à 0.1, 1 PA/PM).
    /// </summary>
    public const double MaxOverWeightPerStat = 101.0;

    /// <summary>
    /// Bonus de stat apporté par une rune selon (stat, rang).
    /// Retourne <c>null</c> si la rune n'existe pas en jeu pour cette combinaison
    /// (ex: pas de Pa PA, pas de Ra Ré%Feu, pas de Ra Dommage Feu, etc.).
    /// </summary>
    public static int? BonusPoints(StatKind stat, RunePower power)
    {
        var id = stat.CharacteristicId;
        // Filtres d'existence des runes
        if (BaseOnlyStats.Contains(id) && power != RunePower.Base) return null;
        if (BaseAndPaOnlyStats.Contains(id) && power == RunePower.Ra) return null;

        switch (id)
        {
            case 11: // Vitalité — runes Vi/PaVi/RaVi
                return power switch
                {
                    RunePower.Base => 5,
                    RunePower.Pa => 15,
                    RunePower.Ra => 50,
                    _ => null
                };
            case 44: // Initiative — uniquement Ra Ini en jeu (densité 100)
                // En réalité darckoune ne liste que value=10 pour Ini, mais en Dofus 3
                // moderne il y a Ini/PaIni/RaIni. On garde 10/30/100.
                return power switch
                {
                    RunePower.Base => 10,
                    RunePower.Pa => 30,
                    RunePower.Ra => 100,
                    _ => null
                };
            case 40: // Pods
                return power switch
                {
                    RunePower.Base => 4,
                    RunePower.Pa => 10,
                    RunePower.Ra => 20,
                    _ => null
                };
            default:
                // Stats standards : densité 1/3/10
                return power switch
                {
                    RunePower.Base => 1,
                    RunePower.Pa => 3,
                    RunePower.Ra => 10,
                    _ => null
                };
        }
    }

    /// <summary>Poids unitaire d'une stat. Fallback à 1.0 si stat inconnue.</summary>
    public static double UnitWeight(StatKind stat) =>
        UnitWeightsById.TryGetValue(stat.CharacteristicId, out var w) ? w : 1.0;

    /// <summary>
    /// Poids total d'une rune dans le puits = <c>bonus_points × unit_weight</c>.
    /// Retourne null si la rune n'existe pas pour cette stat.
    /// </summary>
    public static double? Weight(Rune rune)
    {
        var bonus = BonusPoints(rune.Kind, rune.Power);
        if (bonus is null) return null;
        return bonus.Value * UnitWeight(rune.Kind);
    }

    /// <summary>
    /// Cap d'over en points de stat pour une stat donnée (101 / poids_unitaire).
    /// Ex: Vita (0.25) → 404 points d'over, PA (100) → 1.01 → 1 point d'over max.
    /// </summary>
    public static int MaxOverPoints(StatKind stat)
    {
        var unit = UnitWeight(stat);
        if (unit <= 0) return 0;
        return (int)(MaxOverWeightPerStat / unit);
    }

    /// <summary>
    /// Liste exhaustive des runes existantes pour une stat donnée.
    /// Utile pour itérer sur les rangs disponibles dans les stratégies.
    /// </summary>
    public static IReadOnlyList<Rune> AvailableRunes(StatKind stat)
    {
        var id = stat.CharacteristicId;
        if (BaseOnlyStats.Contains(id))
            return new[] { new Rune(stat, RunePower.Base) };
        if (BaseAndPaOnlyStats.Contains(id))
            return new[] { new Rune(stat, RunePower.Base), new Rune(stat, RunePower.Pa) };
        return new[]
        {
            new Rune(stat, RunePower.Base),
            new Rune(stat, RunePower.Pa),
            new Rune(stat, RunePower.Ra),
        };
    }
}
