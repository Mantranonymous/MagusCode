namespace MagusBot.Core.Models;

/// <summary>
/// "Spec" canonique d'un item, alimentée par DofusDB (table ref_items + ref_item_effects).
/// Contrairement à <see cref="Item"/> qui représente l'état courant lu via OCR (Swift) ou
/// extrait du protocole réseau (C#), <see cref="ItemSpec"/> est statique et nous dit
/// exactement quelles stats peuvent figurer sur l'item et leurs ranges théoriques.
/// </summary>
public sealed record ItemSpec(
    int Id,
    string Name,
    int Level,
    int? TypeId,
    string? TypeName,
    IReadOnlyList<StatSpec> Stats)
{
    public static ItemSpec Create(int id, string name, int level, int? typeId = null, string? typeName = null, IReadOnlyList<StatSpec>? stats = null)
        => new(id, name, level, typeId, typeName, stats ?? Array.Empty<StatSpec>());

    /// <summary>Retourne la spec d'une stat si elle est dans les possibleEffects.</summary>
    public StatSpec? Spec(StatKind kind) => Stats.FirstOrDefault(s => s.Kind == kind);

    public int MinLevelRequired => Level;
}
