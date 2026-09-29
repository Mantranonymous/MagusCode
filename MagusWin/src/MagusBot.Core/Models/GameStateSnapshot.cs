namespace MagusBot.Core.Models;

/// <summary>
/// Snapshot complet de l'état de la session forgemagie à un instant T.
/// Côté Swift c'était le résultat OCR → parsers. Côté C# bot socket, c'est
/// le résultat des packets réseau décodés → StateUpdater.
/// </summary>
public sealed record GameStateSnapshot(
    DateTimeOffset Timestamp,
    Item? Item,
    IReadOnlyList<MageHistoryEntry> History,
    Reliquat? Reliquat,
    int? JobLevel,
    string? JobName)
{
    public static GameStateSnapshot Empty(DateTimeOffset? timestamp = null)
        => new(timestamp ?? DateTimeOffset.UtcNow, null, Array.Empty<MageHistoryEntry>(), null, null, null);

    public bool HasItem => Item is not null;
    public bool HasReliquat => Reliquat?.HasCapacity == true;
    public MageHistoryEntry? LastCombine => History.Count > 0 ? History[^1] : null;
}
