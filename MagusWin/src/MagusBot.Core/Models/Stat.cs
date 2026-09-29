namespace MagusBot.Core.Models;

/// <summary>
/// Compteur de runes disponibles dans l'inventaire pour une stat donnée,
/// tel que lu dans les colonnes Pa/Ra de la stats table Dofus 3.
/// </summary>
public sealed record StatRuneAvailability(int BaseCount = 0, int PaCount = 0, int RaCount = 0)
{
    public bool HasAny => BaseCount > 0 || PaCount > 0 || RaCount > 0;
}

/// <summary>
/// Une stat lue sur un item : type, valeur courante, range, et runes dispos.
/// </summary>
public sealed record Stat(
    StatKind Kind,
    int Value,
    int? MinValue = null,
    int? MaxValue = null,
    StatRuneAvailability? Availability = null)
{
    public int? DistanceToMax => MaxValue is { } max ? max - Value : null;
    public int? DistanceToMin => MinValue is { } min ? Value - min : null;
    public bool IsAtMax => MaxValue is { } max && Value >= max;
    public bool IsAtMin => MinValue is { } min && Value <= min;

    /// <summary>% de progression entre min et max (0...1). null si pas de range.</summary>
    public double? RangeProgress =>
        (MinValue, MaxValue) is ({ } min, { } max) && max > min
            ? (double)(Value - min) / (max - min)
            : null;
}
