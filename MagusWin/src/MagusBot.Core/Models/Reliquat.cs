namespace MagusBot.Core.Models;

/// <summary>
/// Reliquat (puits) : densité de stats sortantes accumulée et disponible.
/// Concept central de la FM Dofus — voir CLAUDE.md du projet Swift d'origine.
///
/// La densité peut être fractionnaire (ex: 2.2) car les runes ont des poids
/// non-entiers selon la stat ciblée.
/// </summary>
public readonly record struct Reliquat
{
    public double Density { get; }

    public Reliquat(double density) => Density = Math.Max(0, density);

    public bool IsEmpty => Density == 0;
    public bool HasCapacity => Density > 0;

    /// <summary>Peut-on poser une rune sans toucher aux stats de l'item ?</summary>
    public bool CanAbsorb(double runeDensity) => Density >= runeDensity;

    /// <summary>Reliquat après absorption d'une rune (typique en cas de SC).</summary>
    public Reliquat Consuming(double runeDensity) => new(Math.Max(0, Density - runeDensity));

    /// <summary>Reliquat après une perte (typique en cas de chute d'une grosse stat).</summary>
    public Reliquat Gaining(double lostDensity) => new(Density + lostDensity);

    /// <summary>Formatage compact pour l'UI ("2.2" ou "27").</summary>
    public string Formatted => Density % 1 == 0
        ? Density.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)
        : Density.ToString("F1", System.Globalization.CultureInfo.InvariantCulture);
}
