using MagusBot.Core.Models;

namespace MagusBot.Core;

/// <summary>
/// Modèle de probabilité SC/SN/EC pour une pose de rune.
///
/// Porté depuis EasyFM <c>CalculResultat</c> (Configuration.csv + lignes 437-556).
/// Formule à 5 cas pondérés : niveau d'item, poids rune, état de la stat,
/// état global du PWRG (poids total de l'item), bonus over/exo.
///
/// <b>Ces probabilités sont une estimation</b> — Ankama n'a jamais publié la
/// vraie formule. Le modèle EasyFM est calibré empiriquement et reste
/// la meilleure approximation publique disponible.
/// </summary>
public sealed class SuccessProbabilityModel
{
    public sealed record Probabilities(double Sc, double Sn, double Ec)
    {
        public string Summary
        {
            get
            {
                static int Pct(double v) => (int)Math.Round(v * 100);
                return $"SC {Pct(Sc)}% · SN {Pct(Sn)}% · EC {Pct(Ec)}%";
            }
        }
    }

    /// <summary>Inputs nécessaires au calcul.</summary>
    public sealed record Inputs(
        Rune Rune,
        int StatCurrentValue,
        int StatMin,
        int StatMax,
        int ItemLevel,
        double PwrgCurrent,
        double PwrgMax,
        double PwrgCurrentStat,
        bool IsExo = false,
        bool IsOver = false,
        double PwrgOverEtExo = 0);

    public Probabilities Compute(Inputs inputs)
    {
        var runeWeight = RuneWeights.Weight(inputs.Rune);
        var runeBonus = RuneWeights.BonusPoints(inputs.Rune.Kind, inputs.Rune.Power);
        if (runeWeight is null || runeBonus is null)
            return new Probabilities(0, 0, 1);

        // Cap dur 1 : si pose impossible (over absolu), EC=100%.
        if (inputs.PwrgOverEtExo + runeWeight > 100.0)
            return new Probabilities(0, 0, 1);

        // Cap dur 2 : exo lourd (rune > 50 de poids) → ~1% SC.
        // Concerne Ga Pa (100), Ga Pm (90), Po (51).
        if (inputs.IsExo && runeWeight > 50.0)
            return new Probabilities(0.01, 0, 0.99);

        // EtatPWR ∈ [0, 1+] : où en est la stat dans sa range ?
        var span = Math.Max(1, inputs.StatMax - inputs.StatMin);
        var projected = inputs.StatCurrentValue + runeBonus.Value;
        var etatPwr = (double)(projected - inputs.StatMin) / span;

        // EtatPWRG ∈ [0, 1+] : où en est le poids total de l'item ?
        var pwrgDenom = Math.Max(1.0, inputs.PwrgMax - inputs.PwrgCurrentStat);
        var etatPwrg = inputs.PwrgCurrent / pwrgDenom;

        // Coefficients de pondération (EasyFM).
        var coefLvl = Math.Max(0.4, 1.0 - (inputs.ItemLevel / 200.0) / 6.0);
        var coefRune = Math.Max(0.4, 1.0 - runeWeight.Value / 200.0);
        var coefOvermax = inputs.IsOver
            ? Math.Max(0.05, (1.0 - (inputs.PwrgOverEtExo + runeWeight.Value) / 100.0) / 2.0)
            : 1.0;

        // Formule de base : SC entre 0 et 80, pondéré par les 3 coefs.
        var rawSc = 80.0 - (20.0 * etatPwr + 30.0 * etatPwrg);
        var sc = (rawSc * coefLvl * coefRune * coefOvermax) / 100.0;
        sc = Math.Max(0, Math.Min(1, sc));

        // SN nominale 50%, perturbée par les coefs aussi.
        var sn = 0.50;
        if (inputs.IsOver || inputs.IsExo)
        {
            var rawSn = 50.0 - 16.0 * (etatPwr + etatPwrg) / 2.0;
            sn = Math.Max(0, Math.Min(1, rawSn / 100.0));
        }

        // EC = reste.
        var ec = Math.Max(0, 1.0 - sc - sn);

        // Bornes empiriques (hors exo/over) : SC ≥ 15%, EC ≤ 35%.
        if (!inputs.IsExo && !inputs.IsOver)
        {
            if (sc < 0.15)
            {
                var delta = 0.15 - sc;
                sc = 0.15;
                ec = Math.Max(0, ec - delta);
            }
            if (ec > 0.35)
            {
                var delta = ec - 0.35;
                ec = 0.35;
                sn += delta;
            }
        }

        // Renormalisation finale.
        var total = sc + sn + ec;
        if (total > 0)
        {
            sc /= total;
            sn /= total;
            ec /= total;
        }

        return new Probabilities(sc, sn, ec);
    }
}
