namespace MagusBot.Core.Models;

/// <summary>
/// Représente l'item posé sur l'établi (avec son état courant).
/// </summary>
public sealed record Item(
    Guid Id,
    int? ReferenceItemId,
    string Name,
    int? Level,
    int? TypeId,
    IReadOnlyList<Stat> Stats,
    IReadOnlyList<Pute> Exos)
{
    public static Item Create(
        string name,
        int? referenceItemId = null,
        int? level = null,
        int? typeId = null,
        IReadOnlyList<Stat>? stats = null,
        IReadOnlyList<Pute>? exos = null)
        => new(
            Guid.NewGuid(),
            referenceItemId,
            name,
            level,
            typeId,
            stats ?? Array.Empty<Stat>(),
            exos ?? Array.Empty<Pute>());

    public Stat? StatMatching(StatKind kind) =>
        Stats.FirstOrDefault(s => s.Kind == kind);
}

/// <summary>
/// Une "pute" (exo) — modification rare obtenue via combine spécifique.
/// </summary>
public sealed record Pute(PuteSlot Slot, int Value);

public enum PuteSlot
{
    Pa,
    Pm,
    Ra,
    Crit,
    Inv,
    Dommages,
    Portee
}
