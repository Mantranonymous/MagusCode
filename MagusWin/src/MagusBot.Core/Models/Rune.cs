namespace MagusBot.Core.Models;

/// <summary>
/// Rang d'une rune. Les bonus listés sont indicatifs pour une stat "neutre"
/// (ex: Force) — les vrais bonus varient légèrement selon la stat. La densité
/// (poids) est la vraie mesure pertinente pour la FM.
/// </summary>
public enum RunePower
{
    /// <summary>Rune de base — densité 1, bonus +1 (ex: Rune Fo).</summary>
    Base = 0,
    /// <summary>Rune PA — densité 3, bonus +3 (ex: Rune Pa Fo).</summary>
    Pa = 1,
    /// <summary>Rune RA — densité 10, bonus +10 (ex: Rune Ra Fo).</summary>
    Ra = 2
}

public static class RunePowerExtensions
{
    /// <summary>Densité (poids) standard de ce rang.</summary>
    public static int Density(this RunePower power) => power switch
    {
        RunePower.Base => 1,
        RunePower.Pa => 3,
        RunePower.Ra => 10,
        _ => throw new ArgumentOutOfRangeException(nameof(power))
    };

    /// <summary>Préfixe affiché dans le nom (ex: "Ra Fo" → "Ra").</summary>
    public static string Prefix(this RunePower power) => power switch
    {
        RunePower.Base => "",
        RunePower.Pa => "Pa",
        RunePower.Ra => "Ra",
        _ => ""
    };

    /// <summary>Identifiant string court conservé pour compatibilité d'affichage.</summary>
    public static string ShortLabel(this RunePower power) => power switch
    {
        RunePower.Base => "base",
        RunePower.Pa => "pa",
        RunePower.Ra => "ra",
        _ => "?"
    };
}

/// <summary>
/// Une rune de forgemagie : rang × stat ciblée.
/// </summary>
public readonly record struct Rune(StatKind Kind, RunePower Power)
{
    /// <summary>Densité totale (= densité du rang).</summary>
    public int Density => Power.Density();
}
